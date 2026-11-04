package fun.nightwell.chat;

import android.app.*;
import android.Manifest;
import android.content.pm.PackageManager;
import android.content.*;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.media.MediaRecorder;
import android.media.MediaPlayer;
import android.media.MediaMetadataRetriever;
import android.os.*;
import android.provider.ContactsContract;
import android.provider.OpenableColumns;
import android.provider.MediaStore;
import android.view.*;
import android.widget.*;
import androidx.core.content.FileProvider;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
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
    static final int PICK_AVATAR=12, PICK_ATTACHMENT=13, PICK_CONTACT=14, CAPTURE_VIDEO=15;
    final ExecutorService network=Executors.newFixedThreadPool(3);
    final Handler handler=new Handler(Looper.getMainLooper());
    String token="", screen="", chatTitle="";
    String nightwellState = "Проверка…";
    TextView nightwellStateView;
    private boolean hasNetwork() {
        android.net.ConnectivityManager manager =
            (android.net.ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
        if (manager == null) return false;
        if (Build.VERSION.SDK_INT >= 23) return manager.getActiveNetwork() != null;
        android.net.NetworkInfo info = manager.getActiveNetworkInfo();
        return info != null && info.isConnected();
    }
    private void updateNightwellState(String state) {
        nightwellState = state;
        if (nightwellStateView != null) {
            nightwellStateView.setText("● Nightwell · " + state);
            nightwellStateView.setTextColor(state.equals("Онлайн") ? 0xff64d98b :
                state.equals("Ограничен") ? 0xffffbd64 : MUTED);
        }
    }
    private final Runnable nightwellPoll = new Runnable() {
        @Override public void run() {
            if (isDestroyed()) return;
            network.execute(() -> {
                String next;
                if (!hasNetwork()) next = "Оффлайн";
                else {
                    HttpURLConnection connection = null;
                    try {
                        connection = (HttpURLConnection) new URL(HOST + "/health").openConnection();
                        connection.setConnectTimeout(4000);
                        connection.setReadTimeout(4000);
                        connection.setRequestProperty("Accept", "application/json");
                        connection.setUseCaches(false);
                        int status = connection.getResponseCode();
                        String contentType = connection.getContentType();
                        boolean json = contentType != null && contentType.contains("json");
                        boolean success = status == 200 && json &&
                            new JSONObject(new String(read(connection.getInputStream(), 4096),
                                StandardCharsets.UTF_8)).optBoolean("ok", false);
                        next = success ? "Онлайн" : "Ограничен";
                    } catch (Exception e) { next = hasNetwork() ? "Ограничен" : "Оффлайн"; }
                    finally { if (connection != null) connection.disconnect(); }
                }
                final String result = next;
                handler.post(() -> {
                    if (isDestroyed() || isFinishing()) return;
                    updateNightwellState(result);
                    handler.removeCallbacks(nightwellPoll);
                    handler.postDelayed(nightwellPoll, 12000);
                });
            });
        }
    };
    int chatId=-1, otherId=-1, meId=-1;
    JSONObject myself;
    LinearLayout page, messages;
    ScrollView scroller;
    boolean loading=false;
    JSONArray cachedChats=new JSONArray();
    String inboxQuery=""; boolean personalOnly=false;
    final java.util.TreeMap<Integer,JSONObject> messageCache=new java.util.TreeMap<>();
    int replyId=-1,lastRenderedId=0; String replyName="";
    TextView replyBanner; EditText composer;
    boolean videoMode=false,mediaHeld=false;
    final java.util.Set<Integer> selectedPeople=new java.util.HashSet<>();
    MediaRecorder voiceRecorder;
    File voiceFile;
    Button voiceButton;
    MediaPlayer voicePlayer;
    int playingVoiceID=-1;
    int requestedVoiceID=-1;
    long voicePlaybackGeneration=0;
    int voicePlaybackChatID=-1;
    String voicePlaybackToken="";
    long voiceStartedAt=0;
    final Handler voiceHandler=new Handler(Looper.getMainLooper());
    final Runnable voiceTimeout=()->{if(voiceRecorder!=null)finishVoice();};
    final Runnable refresh=new Runnable(){ @Override public void run(){
        if("chat".equals(screen)){loadMessages(false);checkIncoming();}
        else if("inbox".equals(screen)){loadChats();checkIncoming();}
        else if("calls".equals(screen)){checkIncoming();}
        if("chat".equals(screen)||"inbox".equals(screen)||"calls".equals(screen))handler.postDelayed(this,6500);
    }};
    interface Job {byte[] call() throws Exception;}
    interface Done {void accept(byte[] data) throws Exception;}

    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        // Android 15+ enforces edge-to-edge. The chat composer must respect IME insets.
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        getWindow().setStatusBarColor(BG);getWindow().setNavigationBarColor(BG);
        token=getPreferences(0).getString("accessToken","");
        ChatPushService.makeChannels(this);
        if(Build.VERSION.SDK_INT>=33 &&
          checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},101);
        if(token.isEmpty())phoneLogin(false); else getMe(false);
    }
    @Override protected void onResume(){super.onResume();handler.removeCallbacks(nightwellPoll);handler.post(nightwellPoll);}
    @Override protected void onPause(){handler.removeCallbacks(nightwellPoll);super.onPause();}
    @Override protected void onDestroy(){stopVoicePlayback();cancelVoice();handler.removeCallbacks(nightwellPoll);handler.removeCallbacks(refresh);network.shutdownNow();super.onDestroy();}

    int dp(int n){return (int)(n*getResources().getDisplayMetrics().density);}
    GradientDrawable shape(int color){GradientDrawable g=new GradientDrawable();g.setColor(color);g.setCornerRadius(dp(14));g.setStroke(dp(1),0xff333333);return g;}
    TextView label(String str,int size,int color){TextView t=new TextView(this);t.setText(str);t.setTextSize(size);t.setTextColor(color);t.setPadding(dp(3),dp(5),dp(3),dp(5));return t;}
    void enter(String dest){
        stopVoicePlayback();
        if(voiceRecorder!=null && !"chat".equals(dest))cancelVoice();
        screen=dest;handler.removeCallbacks(refresh);
        scroller=new ScrollView(this);scroller.setFillViewport(true);
        page=new LinearLayout(this);page.setOrientation(1);page.setPadding(dp(16),dp(24),dp(16),dp(22));page.setBackgroundColor(BG);
        nightwellStateView = label("",11,MUTED);
        nightwellStateView.setContentDescription("Состояние подключения Nightwell");
        updateNightwellState(nightwellState);
        page.addView(nightwellStateView);
        applyWindowInsets(page, dp(24), dp(22));
        scroller.addView(page);setContentView(scroller);
        ViewCompat.requestApplyInsets(page);
    }
    private void applyWindowInsets(LinearLayout content, int topPadding, int bottomPadding) {
        // Insets keep the input visible above both the soft keyboard and gesture navigation.
        // The base padding is reapplied each time; no cumulative growth on IME animations.
        ViewCompat.setOnApplyWindowInsetsListener(content, (view, insets) -> {
            Insets top = insets.getInsets(WindowInsetsCompat.Type.statusBars()
                    | WindowInsetsCompat.Type.displayCutout());
            Insets bottom = insets.getInsets(WindowInsetsCompat.Type.ime()
                    | WindowInsetsCompat.Type.navigationBars());
            view.setPadding(view.getPaddingLeft(), topPadding + top.top,
                    view.getPaddingRight(), bottomPadding + bottom.bottom);
            return insets;
        });
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
    void perform(Job j,Done done){network.execute(()->{try{byte[] b=j.call();runOnUiThread(()->{try{done.accept(b);}catch(Exception x){note(x.toString());}});}catch(Exception x){runOnUiThread(()->loading=false);note(x.getMessage()==null?x.toString():x.getMessage());}});}
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
            c.setUseCaches(false);c.setConnectTimeout(20000);c.setReadTimeout(body!=null && mime.startsWith("multipart/")?180000:45000);c.setRequestMethod(method);
            if(!token.isEmpty())c.setRequestProperty("Authorization","Bearer "+token);
            if(body!=null){c.setDoOutput(true);c.setRequestProperty("Content-Type",mime);c.setFixedLengthStreamingMode(body.length);try(OutputStream o=c.getOutputStream()){o.write(body);}}
            int status=c.getResponseCode();InputStream input=status>=400?c.getErrorStream():c.getInputStream();
            byte[] result=input==null?new byte[0]:read(input,55*1024*1024);
            if(status>=400){
                String message="HTTP "+status+" при запросе "+path;
                try{JSONObject err=new JSONObject(new String(result,StandardCharsets.UTF_8));Object detail=err.opt("detail");if(detail instanceof String)message=(String)detail;}catch(Exception ignored){}
                throw new IOException(message);
            }
            return result;
        }finally{c.disconnect();}
    }
    JSONObject json(byte[] bytes)throws Exception{return new JSONObject(new String(bytes,StandardCharsets.UTF_8));}
    JSONArray array(byte[] bytes)throws Exception{return new JSONArray(new String(bytes,StandardCharsets.UTF_8));}

    void login(boolean register){enter("login");heading("NIGHTWELL CHAT");
        hint(register?"Регистрация по логину и паролю":"Вход по логину и паролю");
        EditText username=field("Логин (латиница, цифры, _)",false);
        EditText name=register?field("Имя в чатах",false):null;
        EditText password=field("Пароль (минимум 8 символов)",true);
        btn(register?"Зарегистрироваться":"Войти",()->{
            String loginName=username.getText().toString().trim().toLowerCase(java.util.Locale.ROOT);
            String pass=password.getText().toString();
            String displayName=name==null?"":name.getText().toString().trim();
            if(!loginName.matches("[a-z0-9_]{3,24}")){
                note("Логин: 3–24 символа. Только латинские буквы, цифры и _");return;
            }
            if(pass.length()<8||pass.length()>256){
                note("Пароль должен содержать от 8 до 256 символов");return;
            }
            if(register&&(displayName.isEmpty()||displayName.length()>60)){
                note("Укажи имя длиной до 60 символов");return;
            }
            perform(()->{
                JSONObject args=payload("username",loginName,"password",pass);
                if(register)args.put("display_name",displayName);
                return http(register?"/auth/register":"/auth/login","POST",args);
            },b->{JSONObject result=json(b);token=result.getString("access_token");
                getPreferences(0).edit().putString("accessToken",token).apply();getMe(false);
            });
        });
        btn(register?"Уже есть аккаунт? Войти":"Создать аккаунт",()->login(!register));
        hint("Номер телефона не нужен. Логин используется для входа и поиска в чате.");
    }
    void phoneLogin(boolean register){
        enter("login");
        heading("NIGHTWELL CHAT");
        hint(register?"Регистрация по номеру телефона":"Вход по номеру телефона");
        EditText number=field("+79991234567",false);
        number.setInputType(android.text.InputType.TYPE_CLASS_PHONE);
        EditText name=register?field("Имя в чатах",false):null;
        EditText password=field("Пароль (минимум 8 символов)",true);
        btn(register?"Зарегистрироваться":"Войти",()->{
            String phone=number.getText().toString().trim();
            String pass=password.getText().toString();
            String display=name==null?"":name.getText().toString().trim();
            if(phone.length()<8||phone.length()>35){note("Введи номер с кодом страны");return;}
            if(pass.length()<8||pass.length()>256){note("Пароль: от 8 до 256 символов");return;}
            if(register&&display.isEmpty()){note("Укажи имя");return;}
            perform(()->{
                JSONObject args=payload("phone",phone,"password",pass);
                if(register){args.put("display_name",display);args.put("discoverable",false);}
                return http(register?"/auth/phone/register":"/auth/phone/login","POST",args);
            },bytes->{
                JSONObject result=json(bytes);
                token=result.getString("access_token");
                getPreferences(0).edit().putString("accessToken",token).apply();
                getMe(false);
            });
        });
        btn(register?"Уже есть аккаунт? Войти":"Создать аккаунт",()->phoneLogin(!register));
        btn("Войти по логину",()->login(false));
        hint("SMS пока нет: проверяется формат номера, а не владение SIM-картой.");
    }
    void getMe(boolean toProfile){perform(()->http("/me","GET",null),b->{
        myself=json(b);meId=myself.optInt("id");
        ChatPushService.refreshToken(this);
        if(toProfile)profile();else inbox();
    });}
    Button compact(String text,Runnable action){
        Button b=new Button(this);b.setText(text);b.setTextColor(FG);b.setAllCaps(false);b.setTextSize(14);
        b.setMinWidth(0);b.setMinimumWidth(0);b.setPadding(dp(4),0,dp(4),0);b.setBackground(shape(PANEL));b.setOnClickListener(v->action.run());return b;
    }
    void inbox(){
        enter("inbox");page.setPadding(dp(12),dp(8),dp(12),dp(8));
        LinearLayout header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title=label("Чаты",24,FG);header.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        header.addView(compact("＋ Группа",this::createGroupScreen));header.addView(compact("✎",this::search));page.addView(header);
        LinearLayout filters=new LinearLayout(this);
        filters.addView(compact("Все",()->{personalOnly=false;renderChats();}),new LinearLayout.LayoutParams(0,dp(44),1));
        filters.addView(compact("Личные",()->{personalOnly=true;renderChats();}),new LinearLayout.LayoutParams(0,dp(44),1));page.addView(filters);
        EditText query=field("Поиск чатов",false);query.setText(inboxQuery);
        query.addTextChangedListener(new android.text.TextWatcher(){public void beforeTextChanged(CharSequence t,int a,int c,int d){}public void onTextChanged(CharSequence t,int a,int b,int c){inboxQuery=t.toString();renderChats();}public void afterTextChanged(android.text.Editable e){}});
        LinearLayout incoming=new LinearLayout(this);incoming.setOrientation(1);incoming.setTag("incoming");page.addView(incoming);
        LinearLayout list=new LinearLayout(this);list.setOrientation(1);list.setTag("list");
        ScrollView chatScroll=new ScrollView(this);chatScroll.addView(list);page.addView(chatScroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout dock=new LinearLayout(this);
        dock.addView(compact("Контакты",this::search),new LinearLayout.LayoutParams(0,dp(58),1));
        dock.addView(compact("Звонки",this::callsScreen),new LinearLayout.LayoutParams(0,dp(58),1));
        dock.addView(compact("Чаты",this::inbox),new LinearLayout.LayoutParams(0,dp(58),1));
        dock.addView(compact("Настройки",this::profile),new LinearLayout.LayoutParams(0,dp(58),1));page.addView(dock);
        scroller.removeView(page);setContentView(page);
        loadChats();checkIncoming();handler.postDelayed(refresh,6500);
    }
    void loadChats(){if(!"inbox".equals(screen))return;perform(()->http("/chats","GET",null),b->{
        if(!"inbox".equals(screen))return;cachedChats=array(b);renderChats();
    });}
    void renderChats(){
        if(!"inbox".equals(screen))return;
        LinearLayout list=page.findViewWithTag("list");if(list==null)return;list.removeAllViews();
        String q=inboxQuery.trim().toLowerCase(java.util.Locale.ROOT);
        for(int i=0;i<cachedChats.length();i++){
            JSONObject ch=cachedChats.optJSONObject(i);if(ch==null)continue;
            if(personalOnly&&"group".equals(ch.optString("kind")))continue;
            String title=ch.optString("title");JSONObject last=ch.optJSONObject("last_message");
            String preview=last==null?"Новый чат":last.optString("body");if(preview.isEmpty())preview="Вложение";
            if(!q.isEmpty()&&!(title+" "+preview).toLowerCase(java.util.Locale.ROOT).contains(q))continue;
            JSONObject person=ch.optJSONObject("other_user");int target=person==null?-1:person.optInt("id",-1),id=ch.optInt("id");
            LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(0,dp(10),0,dp(10));
            row.addView(avatar(target,title),new LinearLayout.LayoutParams(dp(56),dp(56)));
            LinearLayout words=new LinearLayout(this);words.setOrientation(1);words.setPadding(dp(10),0,0,0);
            TextView name=label(title,18,FG);name.setTypeface(null,1);words.addView(name);
            TextView sub=label(preview,15,MUTED);sub.setMaxLines(1);sub.setEllipsize(android.text.TextUtils.TruncateAt.END);words.addView(sub);
            row.addView(words,new LinearLayout.LayoutParams(0,-2,1));
            String date=last==null?"":last.optString("created_at");if(date.length()>=10)date=date.substring(8,10)+"."+date.substring(5,7);else date="";
            int unread=ch.optInt("unread");row.addView(label(date+(unread>0?"\n● "+unread:""),12,MUTED));
            row.setOnClickListener(v->{chatId=id;otherId=target;chatTitle=title;chat();});
            row.setOnLongClickListener(v->{if(last!=null)perform(()->http("/chats/"+id+"/read","POST",new JSONObject().put("message_id",last.optInt("id"))),ok->loadChats());return true;});
            list.addView(row);View line=new View(this);line.setBackgroundColor(0xff222222);list.addView(line,new LinearLayout.LayoutParams(-1,dp(1)));
        }
        if(list.getChildCount()==0)list.addView(label("Чаты не найдены",16,MUTED));
    }
    View avatar(int id,String name){
        FrameLayout box=new FrameLayout(this);GradientDrawable bg=new GradientDrawable();bg.setShape(GradientDrawable.OVAL);
        int[] colors={0xffb17539,0xffa534c1,0xff43a6b7,0xff507de0,0xff509a63};bg.setColor(colors[Math.floorMod(name.hashCode(),colors.length)]);box.setBackground(bg);box.setClipToOutline(true);
        TextView letter=label(name.isEmpty()?"?":name.substring(0,1),26,FG);letter.setGravity(Gravity.CENTER);box.addView(letter,new FrameLayout.LayoutParams(-1,-1));
        ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);box.addView(image,new FrameLayout.LayoutParams(-1,-1));
        if(id>0)network.execute(()->{try{byte[] bytes=http("/users/"+id+"/avatar","GET",null);Bitmap b=BitmapFactory.decodeByteArray(bytes,0,bytes.length);runOnUiThread(()->{if(b!=null)image.setImageBitmap(b);});}catch(Exception ignored){}});
        return box;
    }
    void createGroupScreen(){
        selectedPeople.clear();enter("group");heading("Новая группа");btn("← К чатам",this::inbox);
        EditText title=field("Название группы",false),query=field("Имя или логин участника",false);
        LinearLayout results=new LinearLayout(this);results.setOrientation(1);
        btn("Найти",()->perform(()->http("/users?q="+Uri.encode(query.getText().toString()),"GET",null),b->{
            if(!"group".equals(screen))return;results.removeAllViews();JSONArray people=array(b);
            for(int i=0;i<people.length();i++){JSONObject person=people.getJSONObject(i);int id=person.optInt("id");if(id==meId)continue;
                CheckBox check=new CheckBox(this);check.setText(person.optString("display_name")+" @"+person.optString("username"));check.setTextColor(FG);check.setChecked(selectedPeople.contains(id));
                check.setOnCheckedChangeListener((v,on)->{if(on)selectedPeople.add(id);else selectedPeople.remove(id);});results.addView(check);
            }
        }));page.addView(results);
        btn("Создать группу",()->{String name=title.getText().toString().trim();if(name.isEmpty()||selectedPeople.isEmpty()){note("Укажи название и выбери участников");return;}
            JSONArray ids=new JSONArray();for(int id:selectedPeople)ids.put(id);
            perform(()->http("/chats/groups","POST",new JSONObject().put("title",name).put("user_ids",ids)),b->{JSONObject ch=json(b);chatId=ch.getInt("id");chatTitle=ch.optString("title");otherId=-1;chat();});
        });
    }
    void callsScreen(){enter("calls");heading("Звонки");btn("← К чатам",this::inbox);hint("Входящие звонки");
        LinearLayout incoming=new LinearLayout(this);incoming.setOrientation(1);incoming.setTag("incoming");page.addView(incoming);
        btn("Обновить",this::checkIncoming);checkIncoming();handler.postDelayed(refresh,6500);
    }
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
    void contactProfile(){
        enter("contact_profile");
        btn("← Назад к переписке",this::chat);
        heading(chatTitle);
        page.addView(avatar(otherId,chatTitle),new LinearLayout.LayoutParams(dp(96),dp(96)));
        hint("Профиль собеседника");
        if(otherId>0)hint("ID пользователя: "+otherId);
        if(otherId>0) {
            btn("Позвонить",()->{chat();startCall();});
        }
        btn("Вернуться в чат",this::chat);
    }
    @Override public void onBackPressed(){
        if("contact_profile".equals(screen)){chat();return;}
        if(!"login".equals(screen)&&!"inbox".equals(screen)){inbox();return;}
        super.onBackPressed();
    }
    void chat(){
        enter("chat");messageCache.clear();lastRenderedId=0;replyId=-1;loading=false;
        page.setPadding(dp(10),dp(8),dp(10),dp(8));
        LinearLayout header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);
        header.addView(compact("‹",this::inbox),new LinearLayout.LayoutParams(dp(44),dp(48)));
        TextView title=label(chatTitle,20,FG);title.setMaxLines(1);title.setOnClickListener(v->contactProfile());header.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));
        if(otherId>0)header.addView(compact("☎",this::startCall),new LinearLayout.LayoutParams(dp(48),dp(48)));page.addView(header);
        LinearLayout incoming=new LinearLayout(this);incoming.setOrientation(1);incoming.setTag("incoming");page.addView(incoming);
        ScrollView outer=scroller;outer.removeView(page);
        scroller=new ScrollView(this);scroller.setFillViewport(true);
        messages=new LinearLayout(this);messages.setOrientation(1);scroller.addView(messages);
        page.addView(scroller,new LinearLayout.LayoutParams(-1,0,1));
        replyBanner=label("",13,MUTED);replyBanner.setVisibility(View.GONE);replyBanner.setOnClickListener(v->{replyId=-1;replyBanner.setVisibility(View.GONE);});page.addView(replyBanner);
        LinearLayout compose=new LinearLayout(this);compose.setGravity(Gravity.BOTTOM);
        Button attach=compact("＋",()->new AlertDialog.Builder(this).setTitle("Вложение").setItems(new String[]{"Фото","Файл","Видеокружок"},(d,n)->{
            if(n==2){captureVideo();return;}Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT);pick.addCategory(Intent.CATEGORY_OPENABLE);pick.setType(n==0?"image/*":"*/*");startActivityForResult(pick,PICK_ATTACHMENT);
        }).show());
        compose.addView(attach,new LinearLayout.LayoutParams(dp(48),dp(48)));
        composer=new EditText(this);composer.setTextColor(FG);composer.setHintTextColor(MUTED);composer.setHint("Сообщение");
        composer.setMaxLines(5);composer.setTextSize(16);composer.setInputType(1|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE|android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        composer.setPadding(dp(14),dp(10),dp(14),dp(10));composer.setBackground(shape(PANEL));
        LinearLayout.LayoutParams input=new LinearLayout.LayoutParams(0,-2,1);input.setMargins(dp(8),0,dp(8),0);compose.addView(composer,input);
        voiceButton=compact("🎤",()->{});
        compose.addView(voiceButton,new LinearLayout.LayoutParams(dp(48),dp(48)));
        composer.addTextChangedListener(new android.text.TextWatcher(){public void beforeTextChanged(CharSequence t,int a,int c,int d){}public void onTextChanged(CharSequence t,int a,int b,int c){voiceButton.setText(t.toString().trim().isEmpty()?(videoMode?"◉":"🎤"):"↑");}public void afterTextChanged(android.text.Editable e){}});
        voiceButton.setOnClickListener(v->{if(!composer.getText().toString().trim().isEmpty()){sendDraft();return;}videoMode=!videoMode;voiceButton.setText(videoMode?"◉":"🎤");});
        voiceButton.setOnLongClickListener(v->{
            if(!composer.getText().toString().trim().isEmpty())return false;
            if(videoMode){captureVideo();return true;}
            if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO},102);return true;}
            mediaHeld=true;startVoice();return true;
        });
        voiceButton.setOnTouchListener((v,event)->{if(mediaHeld&&(event.getAction()==MotionEvent.ACTION_UP||event.getAction()==MotionEvent.ACTION_CANCEL)){mediaHeld=false;if(voiceRecorder!=null){if(event.getAction()==MotionEvent.ACTION_CANCEL)cancelVoice();else finishVoice();}return true;}return false;});
        page.addView(compose);
        // This view becomes the window root rather than a ScrollView child.
        // Give it its own IME-aware insets so the composer moves above the keyboard.
        applyWindowInsets(page, dp(8), dp(8));
        setContentView(page);
        ViewCompat.requestApplyInsets(page);
        loadMessages(true);checkIncoming();handler.postDelayed(refresh,6500);
    }
    void sendDraft(){
        String body=composer.getText().toString().trim();if(body.isEmpty())return;int cid=chatId,rid=replyId;
        Button send=voiceButton;send.setEnabled(false);
        network.execute(()->{try{
            JSONObject data=payload("body",body);if(rid>0)data.put("reply_to",rid);http("/chats/"+cid+"/messages","POST",data);
            runOnUiThread(()->{send.setEnabled(true);if("chat".equals(screen)&&chatId==cid){composer.setText("");replyId=-1;replyBanner.setVisibility(View.GONE);loadMessages(true);}});
        }catch(Exception e){runOnUiThread(()->send.setEnabled(true));note(e.getMessage());}});
    }
    void captureVideo(){
        Intent camera=new Intent(this,VideoCircleActivity.class);
        startActivityForResult(camera,CAPTURE_VIDEO);
    }
    void startVoice(){
        try{
            voiceFile=File.createTempFile("nightwell_voice_",".m4a",getCacheDir());
            voiceRecorder=new MediaRecorder();
            voiceRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
            voiceRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            voiceRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
            voiceRecorder.setAudioEncodingBitRate(64000);
            voiceRecorder.setAudioSamplingRate(44100);
            voiceRecorder.setOutputFile(voiceFile.getAbsolutePath());
            voiceRecorder.prepare();
            voiceRecorder.start();
            voiceStartedAt=System.currentTimeMillis();
            voiceHandler.postDelayed(voiceTimeout,120000);
            if(voiceButton!=null)voiceButton.setText("■ Отправить голосовое");
            if(voiceButton!=null)voiceButton.setText("■");
        }catch(Exception e){note("Ошибка микрофона: "+e.getMessage());cancelVoice();}
    }
    void releaseVoice(){
        voiceHandler.removeCallbacks(voiceTimeout);
        if(voiceButton!=null)voiceButton.setText(videoMode?"◉":"🎤");
        if(voiceRecorder!=null){try{voiceRecorder.release();}catch(Exception ignored){} voiceRecorder=null;}
    }
    void cancelVoice(){
        releaseVoice();
        if(voiceFile!=null){voiceFile.delete();voiceFile=null;}
    }
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] grantResults){
        super.onRequestPermissionsResult(requestCode,permissions,grantResults);
        if(requestCode==102){
            if(grantResults.length>0 && grantResults[0]==PackageManager.PERMISSION_GRANTED && "chat".equals(screen))note("Микрофон разрешён. Удерживай кнопку для записи.");
            else note("Для голосовых сообщений нужен доступ к микрофону");
        }
    }
    void finishVoice(){
        if(System.currentTimeMillis()-voiceStartedAt<1000){
            note("Запись слишком короткая");cancelVoice();return;
        }
        try{
            voiceRecorder.stop();
            releaseVoice();
            File recorded=voiceFile;
            int cid=chatId;
            perform(()->{
                byte[] bytes;
                try(FileInputStream in=new FileInputStream(recorded)){bytes=in.readAllBytes();}
                try{return multipart("/chats/"+cid+"/attachments","voice.m4a","audio/mp4",bytes);}
                finally{recorded.delete();}
            },result->loadMessages(true));
        }catch(Exception e){note("Не удалось завершить запись: "+e.getMessage());cancelVoice();}
    }
    void loadMessages(boolean scroll){fetchMessages(scroll,false);}
    void fetchMessages(boolean scroll,boolean older){
        if(loading||!"chat".equals(screen))return;loading=true;int cid=chatId;
        String path="/chats/"+cid+"/messages"+(older&&!messageCache.isEmpty()?"?before="+messageCache.firstKey():"");
        network.execute(()->{try{JSONArray data=array(http(path,"GET",null));runOnUiThread(()->{
            loading=false;if(!"chat".equals(screen)||cid!=chatId)return;
            for(int i=0;i<data.length();i++){JSONObject m=data.optJSONObject(i);if(m!=null)messageCache.put(m.optInt("id"),m);}
            renderMessages(scroll);if(!messageCache.isEmpty()){int last=messageCache.lastKey();network.execute(()->{try{http("/chats/"+cid+"/read","POST",new JSONObject().put("message_id",last));}catch(Exception ignored){}});}
        });}catch(Exception e){runOnUiThread(()->loading=false);note(e.getMessage());}});
    }
    void renderMessages(boolean scroll){
        int previous=lastRenderedId;int y=scroller.getScrollY();messages.removeAllViews();
        if(!messageCache.isEmpty()){Button more=compact("Загрузить ранние",()->fetchMessages(false,true));messages.addView(more);}
        for(JSONObject m:messageCache.values()){
            if(m.optInt("deleted")!=0)continue;
            int id=m.optInt("id");boolean mine=m.optInt("sender_id")==meId;
            LinearLayout item=new LinearLayout(this);item.setOrientation(1);item.setGravity(mine?Gravity.END:Gravity.START);
            TextView sender=label(m.optString("sender_name"),12,MUTED);item.addView(sender);
            if(m.optInt("reply_to")>0){JSONObject original=messageCache.get(m.optInt("reply_to"));item.addView(label("↪ "+(original==null?"Ответ на сообщение":original.optString("body")),12,MUTED));}
            if(!m.optString("body").isEmpty()){TextView body=bubble(m.optString("body"));body.setBackground(shape(mine?0xff26384d:PANEL));item.addView(body);body.setOnLongClickListener(v->{messageActions(m);return true;});}
            item.setOnLongClickListener(v->{messageActions(m);return true;});messages.addView(item);
            JSONObject attachment=m.optJSONObject("attachment");if(attachment!=null)showAttachment(attachment);
            JSONArray reactions=m.optJSONArray("reactions");if(reactions!=null&&reactions.length()>0){StringBuilder text=new StringBuilder();for(int j=0;j<reactions.length();j++){JSONObject r=reactions.optJSONObject(j);if(r!=null)text.append(r.optString("emoji")).append(" ").append(r.optInt("count")).append("  ");}TextView reaction=label(text.toString(),16,FG);messages.addView(reaction);reaction.setOnClickListener(v->pickReaction(id));}
            String date=m.optString("created_at");TextView time=label((date.length()>=16?date.substring(11,16):"")+(m.optString("edited_at","").equals("null")||m.isNull("edited_at")?"":" · изменено"),10,MUTED);messages.addView(time);
            if(previous>0&&id>previous){item.setAlpha(0);item.setTranslationY(dp(18));item.animate().alpha(1).translationY(0).setDuration(240).start();}
        }
        if(!messageCache.isEmpty())lastRenderedId=messageCache.lastKey();
        if(scroll)scroller.post(()->scroller.fullScroll(View.FOCUS_DOWN));else scroller.post(()->scroller.scrollTo(0,y));
    }
    void messageActions(JSONObject m){
        boolean mine=m.optInt("sender_id")==meId;
        String[] options=mine?new String[]{"Ответить","Реакция","Копировать","Изменить","Удалить"}:new String[]{"Ответить","Реакция","Копировать"};
        int id=m.optInt("id");new AlertDialog.Builder(this).setItems(options,(dialog,n)->{
            if(n==0){replyId=id;replyName=m.optString("sender_name");replyBanner.setText("↪ "+replyName+": "+m.optString("body")+"   ✕");replyBanner.setVisibility(View.VISIBLE);composer.requestFocus();}
            if(n==1)pickReaction(id);
            if(n==2)((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("Сообщение",m.optString("body")));
            if(n==3){EditText edit=new EditText(this);edit.setText(m.optString("body"));new AlertDialog.Builder(this).setTitle("Изменить сообщение").setView(edit).setNegativeButton("Отмена",null).setPositiveButton("Сохранить",(d,w)->perform(()->http("/messages/"+id,"PATCH",payload("body",edit.getText().toString())),b->{messageCache.put(id,json(b));renderMessages(false);})).show();}
            if(n==4)new AlertDialog.Builder(this).setMessage("Удалить сообщение?").setNegativeButton("Отмена",null).setPositiveButton("Удалить",(d,w)->perform(()->http("/messages/"+id,"DELETE",null),b->{messageCache.remove(id);renderMessages(false);})).show();
        }).show();
    }
    void pickReaction(int id){String[] emoji={"❤️","🔥","👍","😂","😮","😢"};new AlertDialog.Builder(this).setTitle("Реакция").setItems(emoji,(d,n)->perform(()->http("/messages/"+id+"/reactions","POST",payload("emoji",emoji[n])),b->{messageCache.put(id,json(b));renderMessages(false);})).show();}

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
        }else if(type.startsWith("video/") && name.startsWith("video_circle.")){
            showVideoCircle(attachment);
        }else if(type.startsWith("audio/")){
            LinearLayout voice=new LinearLayout(this);
            voice.setOrientation(LinearLayout.HORIZONTAL);
            voice.setGravity(Gravity.CENTER_VERTICAL);
            voice.setPadding(dp(12),dp(9),dp(12),dp(9));
            voice.setBackground(shape(PANEL));
            TextView play=label(requestedVoiceID==id?"❚❚":"▶",27,FG);
            play.setGravity(Gravity.CENTER);
            voice.addView(play,new LinearLayout.LayoutParams(dp(44),dp(48)));
            LinearLayout bars=new LinearLayout(this);
            bars.setGravity(Gravity.CENTER_VERTICAL);
            for(int i=0;i<29;i++){
                View bar=new View(this);
                bar.setBackgroundColor(0xffcccccc);
                LinearLayout.LayoutParams bp=new LinearLayout.LayoutParams(dp(3),dp(5+(i*17+i*i*3)%22));
                bp.setMargins(dp(1),0,dp(1),0);
                bars.addView(bar,bp);
            }
            voice.addView(bars);
            LinearLayout.LayoutParams vlp=new LinearLayout.LayoutParams(-2,-2);
            vlp.setMargins(0,dp(4),0,dp(9));
            messages.addView(voice,vlp);
            voice.setOnClickListener(v->{
                playVoice(attachment);
                play.setText(requestedVoiceID==id?"❚❚":"▶");
            });
        }else{
            TextView file=bubble((type.startsWith("video/")?"Видеосообщение":name)+"\nНажми, чтобы открыть");
            messages.addView(file);file.setOnClickListener(v->openAttachment(attachment));
        }
    }
    void showVideoCircle(JSONObject attachment){
        int id=attachment.optInt("id");
        FrameLayout circle=new FrameLayout(this);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(190),dp(190));
        lp.setMargins(dp(4),dp(8),dp(4),dp(8));
        messages.addView(circle,lp);
        GradientDrawable bg=new GradientDrawable();
        bg.setShape(GradientDrawable.OVAL);
        bg.setColor(PANEL);
        bg.setStroke(dp(2),0xff555555);
        circle.setBackground(bg);
        circle.setClipToOutline(true);
        ImageView thumbnail=new ImageView(this);
        thumbnail.setScaleType(ImageView.ScaleType.CENTER_CROP);
        circle.addView(thumbnail,new FrameLayout.LayoutParams(-1,-1));
        TextView play=label("▶",38,FG);
        play.setGravity(Gravity.CENTER);
        circle.addView(play,new FrameLayout.LayoutParams(-1,-1));
        circle.setOnClickListener(v->playVideoCircle(attachment));
        perform(()->{
            File folder=new File(getCacheDir(),"circle_thumbnails");
            folder.mkdirs();
            File cached=new File(folder,"frame_"+id+".jpg");
            if(cached.exists())return java.nio.file.Files.readAllBytes(cached.toPath());
            byte[] bytes=http("/attachments/"+id,"GET",null);
            if(bytes.length==0)return new byte[0];
            File temp=new File(getCacheDir(),"video_circle_"+id+".mp4");
            try(FileOutputStream out=new FileOutputStream(temp)){out.write(bytes);}
            MediaMetadataRetriever retriever=new MediaMetadataRetriever();
            try{
                retriever.setDataSource(temp.getAbsolutePath());
                Bitmap frame=retriever.getFrameAtTime(0,MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
                if(frame==null)return new byte[0];
                ByteArrayOutputStream buffer=new ByteArrayOutputStream();
                frame.compress(Bitmap.CompressFormat.JPEG,75,buffer);
                byte[] jpeg=buffer.toByteArray();
                try(FileOutputStream out=new FileOutputStream(cached)){out.write(jpeg);}
                return jpeg;
            }finally{retriever.release();temp.delete();}
        },bytes->{
            Bitmap frame=BitmapFactory.decodeByteArray(bytes,0,bytes.length);
            if(frame!=null)thumbnail.setImageBitmap(frame);
        });
    }
    void playVideoCircle(JSONObject attachment){
        final int id=attachment.optInt("id");
        final int currentChat=chatId;
        final String currentToken=token;
        Dialog dialog=new Dialog(this);
        FrameLayout frame=new FrameLayout(this);
        frame.setBackgroundColor(BG);
        VideoView video=new VideoView(this);
        FrameLayout.LayoutParams vp=new FrameLayout.LayoutParams(dp(280),dp(280),Gravity.CENTER);
        frame.addView(video,vp);
        GradientDrawable mask=new GradientDrawable();
        mask.setShape(GradientDrawable.OVAL);
        mask.setColor(PANEL);
        video.setBackground(mask);
        video.setClipToOutline(true);
        ProgressBar progress=new ProgressBar(this);
        FrameLayout.LayoutParams pp=new FrameLayout.LayoutParams(dp(42),dp(42),Gravity.CENTER);
        frame.addView(progress,pp);
        TextView close=label("✕",26,FG);
        close.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(dp(52),dp(52),Gravity.TOP|Gravity.END);
        frame.addView(close,cp);
        close.setOnClickListener(v->dialog.dismiss());
        dialog.setContentView(frame);
        dialog.setOnDismissListener(d->{video.stopPlayback();});
        dialog.show();
        if(dialog.getWindow()!=null)dialog.getWindow().setLayout(-1,dp(370));
        perform(()->{
            File folder=new File(getCacheDir(),"video_circles");
            folder.mkdirs();
            String name=attachment.optString("filename","video_circle.mp4");
            String extension=name.lastIndexOf('.')>=0?name.substring(name.lastIndexOf('.')):".mp4";
            File file=new File(folder,"circle_"+id+extension.replaceAll("[^a-zA-Z0-9.]",""));
            if(!file.exists()||file.length()==0){
                byte[] bytes=http("/attachments/"+id,"GET",null);
                if(bytes.length==0)throw new IOException("Пустое видеосообщение");
                try(FileOutputStream out=new FileOutputStream(file)){out.write(bytes);}
            }
            return file.getAbsolutePath().getBytes(StandardCharsets.UTF_8);
        },bytes->{
            if(!dialog.isShowing()||currentChat!=chatId||!currentToken.equals(token))return;
            String filePath=new String(bytes,StandardCharsets.UTF_8);
            video.setOnPreparedListener(mp->{
                progress.setVisibility(View.GONE);
                mp.setLooping(true);
                video.start();
            });
            video.setOnErrorListener((mp,what,extra)->{
                progress.setVisibility(View.GONE);
                note("Не удалось воспроизвести видеосообщение");
                return true;
            });
            video.setVideoPath(filePath);
        });
    }
    void stopVoicePlayback(){
        voicePlaybackGeneration++;
        requestedVoiceID=-1;
        playingVoiceID=-1;
        voicePlaybackChatID=-1;
        voicePlaybackToken="";
        if(voicePlayer!=null){
            try{voicePlayer.stop();}catch(Exception ignored){}
            voicePlayer.release();
            voicePlayer=null;
        }
    }
    void playVoice(JSONObject attachment){
        int id=attachment.optInt("id");
        if(requestedVoiceID==id){stopVoicePlayback();return;}
        stopVoicePlayback();
        requestedVoiceID=id;
        voicePlaybackChatID=chatId;
        voicePlaybackToken=token;
        long generation=voicePlaybackGeneration;
        perform(()->http("/attachments/"+id,"GET",null),bytes->{
            if(generation!=voicePlaybackGeneration || !"chat".equals(screen) || chatId!=voicePlaybackChatID || !token.equals(voicePlaybackToken))return;
            if(bytes.length==0){stopVoicePlayback();note("Пустое голосовое сообщение");return;}
            File temp=new File(getCacheDir(),"voice_playback_"+id+".m4a");
            try(FileOutputStream output=new FileOutputStream(temp)){output.write(bytes);}
            try{
                MediaPlayer player=new MediaPlayer();
                player.setDataSource(temp.getAbsolutePath());
                player.setOnCompletionListener(p->{if(voicePlayer==p)stopVoicePlayback();});
                player.prepare();
                voicePlayer=player;
                playingVoiceID=id;
                player.start();
            }catch(Exception e){stopVoicePlayback();note("Не удалось воспроизвести голосовое");}
        });
    }
    void openAttachment(JSONObject attachment){
        int id=attachment.optInt("id");String mime=attachment.optString("content_type","application/octet-stream");
        String name=attachment.optString("filename","file").replaceAll("[^a-zA-Z0-9._-]","_");
        perform(()->http("/attachments/"+id,"GET",null),bytes->{
            File folder=new File(getCacheDir(),"shared");folder.mkdirs();File f=new File(folder,id+"_"+name);
            try(FileOutputStream out=new FileOutputStream(f)){out.write(bytes);}
            Uri uri=FileProvider.getUriForFile(this,getPackageName()+".files",f);
            Intent open=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try{startActivity(Intent.createChooser(open,"Открыть файл"));}catch(Exception e){note("Нет приложения для открытия файла");}
        });
    }
    void profile(){enter("profile");heading("Профиль");btn("← К чатам",this::inbox);
        if(myself==null)return;
        hint("@"+myself.optString("username"));
        hint("Nightwell Chat 0.11.6");
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
            if(settings.isNull("phone")||settings.optString("phone").isEmpty()){
                EditText number=field("+79991234567",false);number.setInputType(3);EditText password=field("Пароль аккаунта",true);
                btn("Привязать номер",()->perform(()->http("/me/phone/link","POST",payload("phone",number.getText().toString(),"password",password.getText().toString()).put("discoverable",false)),ok->profile()));
            }
            CheckBox discoverable=new CheckBox(this);discoverable.setTextColor(FG);
            discoverable.setText("Разрешить поиск по номеру");discoverable.setChecked(settings.optBoolean("discoverable"));
            page.addView(discoverable);
            discoverable.setOnCheckedChangeListener((x,on)->perform(()->http("/me/phone/visibility","PATCH",new JSONObject().put("discoverable",on)),ok->{}));
        });
        btn("Выйти",()->{
            ChatPushService.unregister(this);
            token="";getPreferences(0).edit().remove("accessToken").apply();login(false);
        });
    }
    void startCall(){int id=otherId;if(id<=0)return;perform(()->http("/calls/direct/"+id,"POST",null),b->openCall(json(b)));}
    void checkIncoming(){if(!"inbox".equals(screen)&&!"chat".equals(screen)&&!"calls".equals(screen))return;
        perform(()->http("/calls/pending","GET",null),b->{
            if(!"inbox".equals(screen)&&!"chat".equals(screen)&&!"calls".equals(screen))return;
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
            byte[] data=read(getContentResolver().openInputStream(uri),50*1024*1024);
            String name=filename(uri);String mime=getContentResolver().getType(uri);if(mime==null)mime="application/octet-stream";
            if(avatar){
                Bitmap bitmap=BitmapFactory.decodeByteArray(data,0,data.length);
                if(bitmap==null)throw new IOException("Это не изображение");
                android.media.ExifInterface exif=new android.media.ExifInterface(new ByteArrayInputStream(data));
                int orientation=exif.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION,1);
                android.graphics.Matrix matrix=new android.graphics.Matrix();
                if(orientation==3)matrix.postRotate(180);else if(orientation==6)matrix.postRotate(90);else if(orientation==8)matrix.postRotate(270);
                bitmap=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);
                int side=Math.min(bitmap.getWidth(),bitmap.getHeight());
                bitmap=Bitmap.createBitmap(bitmap,(bitmap.getWidth()-side)/2,(bitmap.getHeight()-side)/2,side,side);
                bitmap=Bitmap.createScaledBitmap(bitmap,512,512,true);
                ByteArrayOutputStream jpg=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.JPEG,85,jpg);
                data=jpg.toByteArray();name="avatar.jpg";mime="image/jpeg";
            }
            byte[] response=multipart(avatar?"/me/avatar":"/chats/"+cid+"/attachments",name,mime,data);
            if(avatar){byte[] verified=http("/users/"+meId+"/avatar","GET",null);if(BitmapFactory.decodeByteArray(verified,0,verified.length)==null)throw new IOException("Сервер не вернул сохранённое фото");}
            return response;
        },ok->{if(avatar)getMe(true);else loadMessages(true);});
    }
    void uploadVideo(Uri uri){
        int cid=chatId;
        perform(()->{
            byte[] data=read(getContentResolver().openInputStream(uri),50*1024*1024);
            String mime=getContentResolver().getType(uri);
            if(mime==null||!mime.startsWith("video/"))mime="video/mp4";
            if(data.length==0)throw new IOException("Пустой видеофайл");
            String extension="video/3gpp".equals(mime)?"3gp":("video/quicktime".equals(mime)?"mov":("video/webm".equals(mime)?"webm":"mp4"));
            return multipart("/chats/"+cid+"/attachments","video_circle."+extension,mime,data);
        },result->loadMessages(true));
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);
        if(result!=RESULT_OK||data==null||data.getData()==null)return;
        Uri uri=data.getData();
        if(request==PICK_AVATAR)upload(uri,true);
        else if(request==PICK_ATTACHMENT)upload(uri,false);
        else if(request==CAPTURE_VIDEO)uploadVideo(uri);
        else if(request==PICK_CONTACT){
            try(Cursor c=getContentResolver().query(uri,new String[]{ContactsContract.CommonDataKinds.Phone.NUMBER},null,null,null)){
                if(c!=null && c.moveToFirst())lookup(c.getString(0));
            }catch(Exception e){note("Не удалось прочитать номер контакта");}
        }
    }
}
