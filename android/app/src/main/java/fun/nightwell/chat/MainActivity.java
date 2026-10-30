package fun.nightwell.chat;

import android.app.*;
import android.content.*;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.*;
import android.provider.ContactsContract;
import android.provider.OpenableColumns;
import android.view.*;
import android.widget.*;
import androidx.core.content.FileProvider;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Native Nightwell Chat client. Only HTTPS connections to the Nightwell server. */
public final class MainActivity extends Activity {
    static final String HOST="https://chat.nightwell.fun";
    static final int BG=0xff080808, PANEL=0xff1a1a1a, FG=0xfff5f5f5, MUTED=0xffaaaaaa;
    static final int PICK_AVATAR=12, PICK_ATTACHMENT=13, PICK_CONTACT=14;
    final ExecutorService network=Executors.newFixedThreadPool(3);
    final Handler handler=new Handler(Looper.getMainLooper());
    String token="", screen="", chatTitle="";
    int chatId=-1, otherId=-1, meId=-1;
    JSONObject myself;
    LinearLayout page, messages;
    ScrollView scroller;
    boolean loading=false;
    final Runnable refresh=new Runnable(){ @Override public void run(){
        if("chat".equals(screen))loadMessages(false);
        else if("inbox".equals(screen)){loadChats();checkIncoming();}
        if("chat".equals(screen)||"inbox".equals(screen))handler.postDelayed(this,6500);
    }};
    interface Job {byte[] call() throws Exception;}
    interface Done {void accept(byte[] data) throws Exception;}

    @Override public void onCreate(Bundle state){
        super.onCreate(state);getWindow().setStatusBarColor(BG);getWindow().setNavigationBarColor(BG);
        token=getPreferences(0).getString("accessToken","");
        if(token.isEmpty())login(false); else getMe(false);
    }
    @Override protected void onDestroy(){handler.removeCallbacks(refresh);network.shutdownNow();super.onDestroy();}

    int dp(int n){return (int)(n*getResources().getDisplayMetrics().density);}
    GradientDrawable shape(int color){GradientDrawable g=new GradientDrawable();g.setColor(color);g.setCornerRadius(dp(14));g.setStroke(dp(1),0xff333333);return g;}
    TextView label(String str,int size,int color){TextView t=new TextView(this);t.setText(str);t.setTextSize(size);t.setTextColor(color);t.setPadding(dp(3),dp(5),dp(3),dp(5));return t;}
    void enter(String dest){
        screen=dest;handler.removeCallbacks(refresh);
        scroller=new ScrollView(this);scroller.setFillViewport(true);
        page=new LinearLayout(this);page.setOrientation(1);page.setPadding(dp(16),dp(24),dp(16),dp(22));page.setBackgroundColor(BG);
        scroller.addView(page);setContentView(scroller);
    }
    void heading(String str){TextView title=label(str,26,FG);title.setTypeface(null,1);page.addView(title);}
    void hint(String str){page.addView(label(str,14,MUTED));}
    EditText field(String placeholder,boolean hidden){
        EditText e=new EditText(this);e.setSingleLine(true);e.setTextColor(FG);e.setHintTextColor(MUTED);
        e.setHint(placeholder);e.setTextSize(16);e.setPadding(dp(15),dp(12),dp(15),dp(12));e.setBackground(shape(PANEL));
        e.setInputType(hidden?129:1);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(0,dp(6),0,dp(9));page.addView(e,lp);return e;
    }
    void btn(String str,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(str);b.setTextColor(FG);b.setBackground(shape(PANEL));
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(48));lp.setMargins(0,dp(5),0,dp(5));page.addView(b,lp);b.setOnClickListener(v->r.run());}
    void note(String s){runOnUiThread(()->new AlertDialog.Builder(this).setTitle("Nightwell Chat").setMessage(s).setPositiveButton("ОК",null).show());}
    void perform(Job j,Done done){network.execute(()->{try{byte[] b=j.call();runOnUiThread(()->{try{done.accept(b);}catch(Exception x){note(x.toString());}});}catch(Exception x){note(x.getMessage()==null?x.toString():x.getMessage());}});}
    JSONObject payload(String... args)throws Exception{JSONObject o=new JSONObject();for(int i=0;i+1<args.length;i+=2)o.put(args[i],args[i+1]);return o;}
    byte[] read(InputStream stream,int max)throws Exception{
        try(InputStream in=stream;ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] chunk=new byte[8192];int count;while((count=in.read(chunk))!=-1){if(out.size()+count>max)throw new IOException("Файл слишком большой");out.write(chunk,0,count);}return out.toByteArray();
        }
    }
    byte[] http(String path,String method,JSONObject input)throws Exception{
        return raw(path,method,input==null?null:input.toString().getBytes(StandardCharsets.UTF_8),"application/json");
    }
    byte[] raw(String path,String method,byte[] body,String mime)throws Exception{
        URL url=new URL(HOST+path);
        HttpURLConnection c=(HttpURLConnection)url.openConnection();
        try{
            c.setConnectTimeout(18000);c.setReadTimeout(35000);c.setRequestMethod(method);
            if(!token.isEmpty())c.setRequestProperty("Authorization","Bearer "+token);
            if(body!=null){c.setDoOutput(true);c.setRequestProperty("Content-Type",mime);try(OutputStream o=c.getOutputStream()){o.write(body);}}
            int status=c.getResponseCode();InputStream input=status>=400?c.getErrorStream():c.getInputStream();
            byte[] result=input==null?new byte[0]:read(input,22*1024*1024);
            if(status>=400){
                String message="HTTP "+status;
                try{JSONObject err=new JSONObject(new String(result,StandardCharsets.UTF_8));Object detail=err.opt("detail");if(detail instanceof String)message=(String)detail;}catch(Exception ignored){}
                throw new IOException(message);
            }
            return result;
        }finally{c.disconnect();}
    }
    JSONObject json(byte[] bytes)throws Exception{return new JSONObject(new String(bytes,StandardCharsets.UTF_8));}
    JSONArray array(byte[] bytes)throws Exception{return new JSONArray(new String(bytes,StandardCharsets.UTF_8));}

    void login(boolean register){enter("login");heading("NIGHTWELL CHAT");
        hint(register?"Создание аккаунта по номеру и паролю":"Вход по номеру телефона и паролю");
        EditText phone=field("+79991234567",false);phone.setInputType(3);
        EditText name=register?field("Твоё имя",false):null;
        EditText password=field("Пароль (минимум 8 символов)",true);
        btn(register?"Зарегистрироваться":"Войти",()->perform(()->{
            JSONObject args=payload("phone",phone.getText().toString().trim(),"password",password.getText().toString());
            if(register){args.put("display_name",name.getText().toString().trim());args.put("discoverable",false);}
            return http(register?"/auth/phone/register":"/auth/phone/login","POST",args);
        },b->{JSONObject result=json(b);token=result.getString("access_token");getPreferences(0).edit().putString("accessToken",token).apply();getMe(false);}));
        btn(register?"Уже есть аккаунт? Войти":"Создать аккаунт",()->login(!register));
        hint("SMS не требуется. Формат номера проверяется сервером, но право владения SIM-картой не подтверждается.");
    }
    void getMe(boolean toProfile){perform(()->http("/me","GET",null),b->{
        myself=json(b);meId=myself.optInt("id");
        if(toProfile)profile();else inbox();
    });}
    void inbox(){enter("inbox");heading("Чаты");
        btn("＋ Новый чат",this::search);
        btn("Мой профиль",this::profile);
        LinearLayout list=new LinearLayout(this);list.setOrientation(1);page.addView(list);list.setTag("list");
        LinearLayout incoming=new LinearLayout(this);incoming.setOrientation(1);page.addView(incoming);incoming.setTag("incoming");
        loadChats();checkIncoming();handler.postDelayed(refresh,6500);
    }
    void loadChats(){if(!"inbox".equals(screen))return;perform(()->http("/chats","GET",null),b->{
        if(!"inbox".equals(screen))return;
        LinearLayout list=(LinearLayout)page.findViewWithTag("list");if(list==null)return;
        list.removeAllViews();JSONArray arr=array(b);
        if(arr.length()==0)list.addView(label("Переписок ещё нет. Найди друга по имени или номеру.",16,MUTED));
        for(int i=0;i<arr.length();i++){
            JSONObject ch=arr.getJSONObject(i);int id=ch.getInt("id");String title=ch.optString("title");
            JSONObject person=ch.optJSONObject("other_user");int target=person==null?-1:person.optInt("id",-1);
            JSONObject last=ch.optJSONObject("last_message");String preview=last==null?"":last.optString("body");
            Button item=new Button(this);item.setAllCaps(false);item.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);
            item.setText(title+(preview.isEmpty()?"":"\n"+preview));item.setTextColor(FG);item.setBackground(shape(PANEL));
            LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(76));p.setMargins(0,dp(6),0,0);list.addView(item,p);
            item.setOnClickListener(v->{chatId=id;otherId=target;chatTitle=title;chat();});
        }
    });}
    void search(){enter("search");heading("Новый чат");btn("← К чатам",this::inbox);
        EditText nick=field("Имя или логин",false);
        btn("Найти пользователя",()->perform(()->http("/users?q="+Uri.encode(nick.getText().toString()),"GET",null),b->{
            showPeople(array(b));
        }));
        EditText phone=field("+79991234567",false);phone.setInputType(3);
        btn("Найти по номеру",()->lookup(phone.getText().toString()));
        btn("Выбрать из контактов",()->{
            Intent picker=new Intent(Intent.ACTION_PICK,ContactsContract.CommonDataKinds.Phone.CONTENT_URI);
            startActivityForResult(picker,PICK_CONTACT);
        });
        hint("Приложение не загружает всю адресную книгу. Проверяется только выбранный номер. Найти можно тех, кто разрешил поиск по телефону.");
    }
    void showPeople(JSONArray matches)throws Exception{
        hint("Результаты поиска:");
        if(matches.length()==0)hint("Никого не найдено.");
        for(int i=0;i<matches.length();i++){
            JSONObject person=matches.getJSONObject(i);
            btn(person.optString("display_name")+"  @"+person.optString("username"),()->openPerson(person));
        }
    }
    void lookup(String phone){perform(()->http("/users/by-phone?phone="+Uri.encode(phone),"GET",null),b->{
        String s=new String(b,StandardCharsets.UTF_8);
        if(s.equals("null"))note("Номер не найден или пользователь скрыл его.");
        else openPerson(json(b));
    });}
    void openPerson(JSONObject user){int id=user.optInt("id");
        perform(()->http("/chats/direct/"+id,"POST",null),b->{
            JSONObject ch=json(b);chatId=ch.getInt("id");otherId=id;chatTitle=ch.optString("title");chat();
        });
    }
    void chat(){enter("chat");heading(chatTitle);btn("← Список чатов",this::inbox);
        if(otherId>0)btn("Позвонить",this::startCall);
        messages=new LinearLayout(this);messages.setOrientation(1);page.addView(messages);
        EditText draft=field("Напиши сообщение...",false);
        btn("Отправить",()->{String msg=draft.getText().toString().trim();if(msg.isEmpty())return;
            int cid=chatId;perform(()->http("/chats/"+cid+"/messages","POST",payload("body",msg)),b->{draft.setText("");loadMessages(true);});
        });
        btn("＋ Фото или файл",()->{
            Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT);pick.addCategory(Intent.CATEGORY_OPENABLE);pick.setType("*/*");
            startActivityForResult(pick,PICK_ATTACHMENT);
        });
        loadMessages(true);handler.postDelayed(refresh,6500);
    }
    void loadMessages(boolean scroll){if(loading||!"chat".equals(screen))return;loading=true;int cid=chatId;
        perform(()->http("/chats/"+cid+"/messages","GET",null),b->{
            loading=false;if(!"chat".equals(screen)||cid!=chatId)return;
            messages.removeAllViews();JSONArray data=array(b);
            for(int i=0;i<data.length();i++){
                JSONObject m=data.getJSONObject(i);
                if(m.optInt("deleted")!=0)continue;
                messages.addView(label(m.optString("sender_name"),13,MUTED));
                String message=m.optString("body");if(!message.isEmpty())messages.addView(bubble(message));
                JSONObject attachment=m.optJSONObject("attachment");if(attachment!=null)showAttachment(attachment);
            }
            if(scroll)scroller.post(()->scroller.fullScroll(View.FOCUS_DOWN));
        });
    }
    TextView bubble(String text){TextView t=label(text,17,FG);t.setPadding(dp(15),dp(11),dp(15),dp(11));t.setBackground(shape(PANEL));
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.setMargins(0,dp(4),0,dp(9));t.setLayoutParams(p);return t;}
    void showAttachment(JSONObject attachment){
        int id=attachment.optInt("id");String name=attachment.optString("filename","file");
        String type=attachment.optString("content_type");
        if(type.startsWith("image/")){
            ImageView image=new ImageView(this);image.setAdjustViewBounds(true);image.setMaxHeight(dp(320));
            messages.addView(image,new LinearLayout.LayoutParams(dp(260),-2));
            perform(()->http("/attachments/"+id,"GET",null),bytes->{
                Bitmap map=BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(map!=null)image.setImageBitmap(map);
            });
            image.setOnClickListener(v->openAttachment(attachment));
        }else{
            TextView file=bubble("📎 "+name+"\nНажми, чтобы открыть");
            messages.addView(file);file.setOnClickListener(v->openAttachment(attachment));
        }
    }
    void openAttachment(JSONObject attachment){
        int id=attachment.optInt("id");String mime=attachment.optString("content_type","application/octet-stream");
        String name=attachment.optString("filename","file").replaceAll("[^a-zA-Z0-9._-]","_");
        perform(()->http("/attachments/"+id,"GET",null),bytes->{
            File folder=new File(getCacheDir(),"shared");folder.mkdirs();File f=new File(folder,name);
            try(FileOutputStream out=new FileOutputStream(f)){out.write(bytes);}
            Uri uri=FileProvider.getUriForFile(this,getPackageName()+".files",f);
            Intent open=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try{startActivity(Intent.createChooser(open,"Открыть файл"));}catch(Exception e){note("Нет приложения для открытия файла");}
        });
    }
    void profile(){enter("profile");heading("Профиль");btn("← К чатам",this::inbox);
        if(myself==null)return;
        hint("@"+myself.optString("username"));
        ImageView avatar=new ImageView(this);avatar.setAdjustViewBounds(true);avatar.setMaxHeight(dp(160));
        avatar.setImageResource(android.R.drawable.sym_def_app_icon);
        page.addView(avatar,new LinearLayout.LayoutParams(dp(120),dp(120)));
        if(myself.optBoolean("has_avatar"))perform(()->http("/users/"+meId+"/avatar","GET",null),bytes->{
            Bitmap b=BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(b!=null)avatar.setImageBitmap(b);
        });
        btn("Изменить аватар",()->{
            Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT);pick.setType("image/*");
            pick.addCategory(Intent.CATEGORY_OPENABLE);startActivityForResult(pick,PICK_AVATAR);
        });
        EditText name=field("Отображаемое имя",false);name.setText(myself.optString("display_name"));
        btn("Сохранить имя",()->perform(()->http("/me","PATCH",payload("display_name",name.getText().toString())),b->{getMe(true);}));
        if(myself.optBoolean("has_avatar"))btn("Удалить аватар",()->perform(()->http("/me/avatar","DELETE",null),b->getMe(true)));
        perform(()->http("/me/phone","GET",null),b->{
            if(!"profile".equals(screen))return;JSONObject settings=json(b);
            hint("Номер: "+settings.optString("phone","не привязан"));
            CheckBox discoverable=new CheckBox(this);discoverable.setTextColor(FG);
            discoverable.setText("Разрешить поиск по номеру");discoverable.setChecked(settings.optBoolean("discoverable"));
            page.addView(discoverable);
            discoverable.setOnCheckedChangeListener((x,on)->perform(()->http("/me/phone/visibility","PATCH",new JSONObject().put("discoverable",on)),ok->{}));
        });
        btn("Выйти",()->{token="";getPreferences(0).edit().remove("accessToken").apply();login(false);});
    }
    void startCall(){int id=otherId;if(id<=0)return;perform(()->http("/calls/direct/"+id,"POST",null),b->openCall(json(b)));}
    void checkIncoming(){if(!"inbox".equals(screen))return;
        perform(()->http("/calls/pending","GET",null),b->{
            if(!"inbox".equals(screen))return;
            LinearLayout row=(LinearLayout)page.findViewWithTag("incoming");if(row==null)return;row.removeAllViews();
            JSONArray pending=array(b);
            for(int i=0;i<pending.length();i++){
                JSONObject call=pending.getJSONObject(i);String cid=call.optString("id");
                TextView info=label("Входящий звонок: "+call.optString("caller_name"),17,FG);row.addView(info);
                Button accept=new Button(this);accept.setText("Ответить");row.addView(accept);
                accept.setOnClickListener(v->perform(()->http("/calls/"+cid+"/accept","POST",null),answer->{
                    JSONObject a=json(answer);a.put("id",cid);openCall(a);
                }));
                Button decline=new Button(this);decline.setText("Отклонить");row.addView(decline);
                decline.setOnClickListener(v->perform(()->http("/calls/"+cid+"/decline","POST",null),ok->checkIncoming()));
            }
        });
    }
    void openCall(JSONObject call){
        String id=call.optString("id"), ticket=call.optString("ticket");
        if(id.isEmpty()||ticket.isEmpty()){note("Не удалось подключиться к звонку");return;}
        Intent intent=new Intent(this,CallActivity.class);
        intent.putExtra("url",HOST+"/calls/"+Uri.encode(id)+"/page#ticket="+Uri.encode(ticket));startActivity(intent);
    }
    String filename(Uri uri){
        try(Cursor c=getContentResolver().query(uri,null,null,null,null)){
            if(c!=null && c.moveToFirst()){int i=c.getColumnIndex(OpenableColumns.DISPLAY_NAME);if(i>=0)return c.getString(i);}
        }catch(Exception ignored){}
        return "file.bin";
    }
    byte[] multipart(String route,String name,String mime,byte[] bytes)throws Exception{
        String boundary="NW"+System.nanoTime();String safe=name.replaceAll("[^a-zA-Z0-9._-]","_");
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        out.write(("--"+boundary+"\r\nContent-Disposition: form-data; name=\"file\"; filename=\""+safe+"\"\r\nContent-Type: "+mime+"\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        out.write(bytes);out.write(("\r\n--"+boundary+"--\r\n").getBytes(StandardCharsets.UTF_8));
        return raw(route,"POST",out.toByteArray(),"multipart/form-data; boundary="+boundary);
    }
    void upload(Uri uri,boolean avatar){
        int cid=chatId;perform(()->{
            byte[] data=read(getContentResolver().openInputStream(uri),16*1024*1024);
            String name=filename(uri);String mime=getContentResolver().getType(uri);if(mime==null)mime="application/octet-stream";
            if(avatar){
                Bitmap bitmap=BitmapFactory.decodeByteArray(data,0,data.length);
                if(bitmap==null)throw new IOException("Это не изображение");
                ByteArrayOutputStream jpg=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.JPEG,85,jpg);
                data=jpg.toByteArray();name="avatar.jpg";mime="image/jpeg";
            }
            return multipart(avatar?"/me/avatar":"/chats/"+cid+"/attachments",name,mime,data);
        },ok->{if(avatar)getMe(true);else loadMessages(true);});
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);
        if(result!=RESULT_OK||data==null||data.getData()==null)return;
        Uri uri=data.getData();
        if(request==PICK_AVATAR)upload(uri,true);
        else if(request==PICK_ATTACHMENT)upload(uri,false);
        else if(request==PICK_CONTACT){
            try(Cursor c=getContentResolver().query(uri,new String[]{ContactsContract.CommonDataKinds.Phone.NUMBER},null,null,null)){
                if(c!=null && c.moveToFirst())lookup(c.getString(0));
            }catch(Exception e){note("Не удалось прочитать номер контакта");}
        }
    }
}
