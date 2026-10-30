package fun.nightwell.chat;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ContentResolver;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.provider.ContactsContract;
import android.text.InputType;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.content.Context;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class MainActivity extends Activity {
    private static final int BG=0xff050505, PANEL=0xff191919, PANEL2=0xff242424;
    private static final int FG=0xfffafafa, MUTED=0xffa1a1a1, STROKE=0xff343434;
    private static final int CONTACT_PERMISSION=71;
    private final List<Contact> contacts=new ArrayList<>();
    private final List<Integer> groupUsers=new ArrayList<>();
    private Backend backend;
    private LinearLayout root, column, toolbar;
    private String screen="", activeTitle="", searchTerm="";
    private int currentChatId=0, myUserId=0;
    private JSONObject currentChat;
    private JSONArray loadedMessages=new JSONArray();
    private boolean showingRegistration=false, showingLegacy=false;
    private TextView contactCount;

    private static class Contact {
        String name,number;
        Contact(String n,String p) { name=n; number=p; }
    }
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        backend=new Backend(this);
        if(backend.signedIn()) bootstrap(); else authScreen();
    }
    @Override public void onBackPressed() {
        if(screen.equals("conversation")) inbox();
        else if(screen.equals("contacts") || screen.equals("new") || screen.equals("group") || screen.equals("settings")) inbox();
        else super.onBackPressed();
    }
    private int dp(int a) { return (int)(a*getResources().getDisplayMetrics().density+0.5f); }
    private GradientDrawable shape(int color,int radius) {
        GradientDrawable s=new GradientDrawable();s.setColor(color);s.setCornerRadius(dp(radius));
        s.setStroke(dp(1), STROKE);return s;
    }
    private TextView text(String value,int size,int color,boolean bold) {
        TextView t=new TextView(this);t.setText(value);t.setTextSize(size);t.setTextColor(color);
        if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        t.setGravity(Gravity.CENTER_VERTICAL);
        return t;
    }
    private LinearLayout vertical() {
        LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.VERTICAL); return v;
    }
    private LinearLayout horizontal() {
        LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;
    }
    private void pad(View v,int all) { v.setPadding(dp(all),dp(all),dp(all),dp(all)); }
    private LinearLayout.LayoutParams lp(int w,int h) { return new LinearLayout.LayoutParams(w<0?w:dp(w),h<0?h:dp(h)); }
    private LinearLayout.LayoutParams spaced(int w,int h,int top) {
        LinearLayout.LayoutParams p=lp(w,h);p.topMargin=dp(top);return p;
    }
    private void begin(String title,boolean back) {
        screen=title;
        root=vertical();root.setBackgroundColor(BG);
        setContentView(root);
        toolbar=horizontal();toolbar.setPadding(dp(18),dp(16),dp(18),dp(12));
        if(back) {
            TextView b=text("‹",36,FG,false); b.setGravity(Gravity.CENTER);
            toolbar.addView(b,lp(44,44));b.setOnClickListener(v->onBackPressed());
        }
        TextView headline=text(screenLabel(title),23,FG,true);headline.setLetterSpacing(0.04f);
        toolbar.addView(headline,new LinearLayout.LayoutParams(0,dp(48),1));
        root.addView(toolbar,lp(-1,-2));
        View line=new View(this);line.setBackgroundColor(STROKE);root.addView(line,lp(-1,1));
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);
        column=vertical();column.setPadding(dp(18),dp(20),dp(18),dp(16));
        scroll.addView(column);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
    }
    private String screenLabel(String s) {
        switch (s) {
            case "auth":return "NIGHTWELL CHAT";
            case "inbox":return "Чаты";
            case "new":return "Новый чат";
            case "contacts":return "Контакты";
            case "group":return "Новая группа";
            case "settings":return "Настройки";
            case "conversation":return activeTitle;
            default:return s;
        }
    }
    private void action(String label,Runnable run) {
        TextView button=text(label,14,FG,false);button.setPadding(dp(14),0,dp(14),0);
        button.setBackground(shape(PANEL,18));button.setGravity(Gravity.CENTER);
        toolbar.addView(button,spaced(-2,42,0));button.setOnClickListener(v->run.run());
    }
    private TextView button(String label,boolean primary,Runnable run) {
        TextView b=text(label,16,primary?BG:FG,true);
        b.setGravity(Gravity.CENTER);b.setBackground(shape(primary?FG:PANEL,16));
        column.addView(b,spaced(-1,50,12));
        b.setOnClickListener(v->run.run());return b;
    }
    private void description(String value) {
        TextView t=text(value,13,MUTED,false);t.setLineSpacing(dp(3),1);
        column.addView(t,spaced(-1,-2,12));
    }
    private void section(String title) { TextView t=text(title,13,MUTED,true);column.addView(t,spaced(-1,-2,20)); }
    private EditText field(String hint,boolean password,boolean phone) {
        EditText e=new EditText(this);e.setTextColor(FG);e.setHintTextColor(MUTED);
        e.setTextSize(16);e.setSingleLine(true);e.setHint(hint);
        e.setBackground(shape(PANEL,14));e.setPadding(dp(15),0,dp(14),0);
        if(phone)e.setInputType(InputType.TYPE_CLASS_PHONE);
        else if(password)e.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);
        else e.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        column.addView(e,spaced(-1,52,11));return e;
    }
    private void row(String name,String subtitle,Runnable tap) {
        LinearLayout wrap=vertical();pad(wrap,15);wrap.setBackground(shape(PANEL,17));
        TextView t=text(name,16,FG,true);wrap.addView(t);
        if(subtitle!=null&&!subtitle.isEmpty()) {
            TextView sub=text(subtitle,12,MUTED,false);sub.setMaxLines(2);sub.setEllipsize(TextUtils.TruncateAt.END);
            wrap.addView(sub,spaced(-1,-2,6));
        }
        column.addView(wrap,spaced(-1,-2,10));wrap.setOnClickListener(v->tap.run());
    }
    private void call(String method,String path,JSONObject body,java.util.function.Consumer<Object> done) {
        backend.run(method,path,body,(value,error)->runOnUiThread(()->{
            if(error!=null) toast(error);
            else done.accept(value);
        }));
    }
    private void toast(String msg) { Toast.makeText(this,msg,Toast.LENGTH_LONG).show(); }
    private static JSONObject data(Object... params) {
        JSONObject j=new JSONObject();
        for(int i=0;i+1<params.length;i+=2) try { j.put((String)params[i],params[i+1]); } catch(JSONException e) { throw new IllegalArgumentException(e); }
        return j;
    }
    private static String param(String value) { return URLEncoder.encode(value,StandardCharsets.UTF_8); }
    private static String str(JSONObject j,String key) {return j.optString(key,"");}
    private void bootstrap() {
        call("GET","/me",null,value->{
            JSONObject me=(JSONObject)value;myUserId=me.optInt("id");inbox();
            backend.watch(()->runOnUiThread(()->{
                if(screen.equals("inbox")) loadInbox();
                else if(screen.equals("conversation")) loadMessages();
            }));
        });
    }
    private void authScreen() {
        begin("auth",false);
        TextView logo=text("◉",64,FG,false);logo.setGravity(Gravity.CENTER);
        logo.setLetterSpacing(0.1f);column.addView(logo,spaced(-1,90,24));
        TextView title=text("Твои люди. Твой ритм.",24,FG,true);title.setGravity(Gravity.CENTER);
        column.addView(title,spaced(-1,38,10));
        description("Личный мессенджер Nightwell с защищённым подключением и чёрно-белым интерфейсом.");
        section(showingRegistration?"РЕГИСТРАЦИЯ":"ВХОД");
        EditText phone=field(showingLegacy?"Имя пользователя":"Номер телефона, +79991234567",false,!showingLegacy);
        EditText name=showingRegistration?field("Отображаемое имя",false,false):null;
        EditText password=field("Пароль (минимум 8 символов)",true,false);
        CheckBox discover=new CheckBox(this);
        discover.setTextColor(MUTED);discover.setText("Разрешить поиск меня по номеру");
        if(showingRegistration&&!showingLegacy)column.addView(discover,spaced(-1,-2,14));
        button(showingRegistration?"Создать аккаунт":"Войти",true,()->{
            String p=phone.getText().toString().trim(),pw=password.getText().toString();
            if(pw.length()<8){toast("Пароль должен быть длиннее 7 символов");return;}
            if(showingRegistration&&name.getText().toString().trim().isEmpty()){toast("Введи имя");return;}
            String route=showingLegacy ? (showingRegistration?"/auth/register":"/auth/login") :
                (showingRegistration?"/auth/phone/register":"/auth/phone/login");
            JSONObject payload=showingLegacy?data("username",p,"password",pw):data("phone",p,"password",pw);
            if(showingRegistration)try {
                payload.put("display_name",name.getText().toString().trim());
                if(!showingLegacy)payload.put("discoverable",discover.isChecked());
            }catch(JSONException ignored){}
            call("POST",route,payload,value->{
                try { backend.accept((JSONObject)value);bootstrap(); }
                catch(Exception e){toast("Не удалось сохранить сессию");}
            });
        });
        button(showingRegistration?"Уже есть аккаунт? Войти":"Нет аккаунта? Зарегистрироваться",false,()->{
            showingRegistration=!showingRegistration;authScreen();
        });
        button(showingLegacy?"Войти по номеру":"Старый аккаунт: логин и пароль",false,()->{
            showingLegacy=!showingLegacy;showingRegistration=false;authScreen();
        });
        description("Без SMS проверяется формат номера, но не его принадлежность. Не используй чужой номер.");
        description("Сервер: "+backend.server());
        button("Адрес сервера",false,()->serverDialog());
    }
    private void inbox() { begin("inbox",false);
        action("+",()->newChat());action("⚙",()->settings());
        description("Личные и групповые переписки · Nightwell");
        button("Обновить",false,()->loadInbox());
        loadInbox();
    }
    private void loadInbox() {
        if(!screen.equals("inbox"))return;
        call("GET","/chats",null,value->{
            if(!screen.equals("inbox"))return;
            JSONArray arr=(JSONArray)value;
            while(column.getChildCount()>2) column.removeViewAt(2);
            if(arr.length()==0) description("Пока нет чатов. Нажми +, чтобы найти человека.");
            for(int i=0;i<arr.length();i++) {
                JSONObject chat=arr.optJSONObject(i);if(chat==null)continue;
                String title=str(chat,"title");
                JSONObject last=chat.optJSONObject("last_message");
                String sub=last==null?"Новая переписка":str(last,"body");
                int unread=chat.optInt("unread");
                row(title+(unread>0?" · "+unread:""),sub,()->openChat(chat));
            }
        });
    }
    private void newChat() { begin("new",true);
        description("Найди человека по имени, имени пользователя или по номеру.");
        EditText query=field("Имя или @username",false,false);
        button("Найти",true,()->{
            String q=query.getText().toString().trim();if(q.isEmpty())return;
            searchTerm=q;
            call("GET","/users?q="+param(q),null,value->{
                JSONArray people=(JSONArray)value;
                while(column.getChildCount()>3) column.removeViewAt(3);
                if(people.length()==0)description("Никого не найдено");
                for(int i=0;i<people.length();i++) {
                    JSONObject person=people.optJSONObject(i);if(person!=null)
                        row(str(person,"display_name"),"@"+str(person,"username"),()->openDirect(person));
                }
            });
        });
        button("Найти по номеру",false,()->phoneDialog(""));
        button("Открыть контакты",false,()->contactsScreen());
        button("Создать группу",false,()->groupScreen());
    }
    private void phoneDialog(String prefill) {
        EditText input=new EditText(this);input.setText(prefill);input.setInputType(InputType.TYPE_CLASS_PHONE);
        input.setTextColor(FG);input.setHint("+79991234567");
        new AlertDialog.Builder(this).setTitle("Поиск по номеру").setMessage("Отправится только выбранный номер. Поиск работает, если человек разрешил находить себя по номеру.")
            .setView(input).setPositiveButton("Найти",(dialog,which)->{
                String num=input.getText().toString().trim();
                call("GET","/users/by-phone?phone="+param(num),null,value->{
                    if(value==JSONObject.NULL){toast("Пользователь не найден или скрыл номер");return;}
                    JSONObject p=(JSONObject)value;
                    new AlertDialog.Builder(this).setTitle(str(p,"display_name"))
                        .setMessage("Найден аккаунт Nightwell Chat. Номер не подтверждён через SMS.")
                        .setPositiveButton("Открыть чат",(d,w)->openDirect(p))
                        .setNegativeButton("Отмена",null).show();
                });
            }).setNegativeButton("Отмена",null).show();
    }
    private void openDirect(JSONObject p) {
        call("POST","/chats/direct/"+p.optInt("id"),data(),value->openChat((JSONObject)value));
    }
    private void contactsScreen() {
        begin("contacts",true);
        description("Контакты читаются только на устройстве. На сервер передаётся один выбранный номер, а не вся адресная книга.");
        if(checkSelfPermission(Manifest.permission.READ_CONTACTS)!=PackageManager.PERMISSION_GRANTED) {
            button("Разрешить доступ к контактам",true,()->requestPermissions(new String[]{Manifest.permission.READ_CONTACTS},CONTACT_PERMISSION));
            return;
        }
        readContacts();
    }
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] results) {
        super.onRequestPermissionsResult(requestCode,permissions,results);
        if(requestCode==CONTACT_PERMISSION&&screen.equals("contacts")) {
            if(results.length>0&&results[0]==PackageManager.PERMISSION_GRANTED)contactsScreen();
            else toast("Доступ к контактам не предоставлен");
        }
    }
    private void readContacts() {
        contacts.clear();
        ContentResolver resolver=getContentResolver();
        String[] projection={ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,ContactsContract.CommonDataKinds.Phone.NUMBER};
        try(Cursor c=resolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI,projection,null,null,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME+" ASC")) {
            if(c!=null)while(c.moveToNext()) {
                String name=c.getString(0), number=c.getString(1);
                if(number!=null&&!number.trim().isEmpty())contacts.add(new Contact(name==null?"Без имени":name,number));
            }
        }catch(SecurityException e){toast("Нет доступа к контактам");return;}
        EditText filter=field("Поиск по контактам",false,false);
        LinearLayout results=vertical();column.addView(results,spaced(-1,-2,12));
        Runnable render=()->{
            results.removeAllViews();String q=filter.getText().toString().toLowerCase();
            for(Contact c:contacts)if(c.name.toLowerCase().contains(q)||c.number.contains(q)) {
                LinearLayout pane=vertical();pad(pane,14);pane.setBackground(shape(PANEL,15));
                pane.addView(text(c.name,16,FG,true));pane.addView(text(c.number,13,MUTED,false));
                results.addView(pane,spaced(-1,-2,7));
                pane.setOnClickListener(v->phoneDialog(c.number));
            }
        };
        filter.addTextChangedListener(new android.text.TextWatcher(){
            public void beforeTextChanged(CharSequence s,int start,int count,int after){}
            public void onTextChanged(CharSequence s,int start,int before,int count){render.run();}
            public void afterTextChanged(android.text.Editable s){}
        });
        render.run();
    }
    private void groupScreen() {
        groupUsers.clear();
        groupBuilder();
    }
    private void groupBuilder() {
        begin("group",true);
        EditText title=field("Название группы",false,false);
        EditText q=field("Найти участника по имени",false,false);
        button("Найти участника",false,()->{
            String name=q.getText().toString().trim();if(name.isEmpty())return;
            call("GET","/users?q="+param(name),null,value->{
                JSONArray arr=(JSONArray)value;
                for(int i=0;i<arr.length();i++) {
                    JSONObject user=arr.optJSONObject(i);if(user==null)continue;
                    int id=user.optInt("id");
                    row(str(user,"display_name"),groupUsers.contains(id)?"Добавлен":"Нажми для добавления",()->{
                        if(!groupUsers.contains(id))groupUsers.add(id);
                        toast("Добавлен участник: "+str(user,"display_name"));
                    });
                }
            });
        });
        button("Создать группу",true,()->{
            String name=title.getText().toString().trim();if(name.isEmpty()){toast("Введи название группы");return;}
            JSONArray ids=new JSONArray();for(Integer id:groupUsers)ids.put(id);
            call("POST","/chats/groups",data("title",name,"user_ids",ids),value->openChat((JSONObject)value));
        });
        description("Добавляй участников через поиск и затем нажми «Создать группу».");
    }
    private void openChat(JSONObject chat) {
        currentChat=chat;currentChatId=chat.optInt("id");activeTitle=str(chat,"title");
        begin("conversation",true);
        action("⟳",()->loadMessages());
        loadMessages();
        LinearLayout composer=horizontal();composer.setPadding(dp(14),dp(10),dp(14),dp(13));
        EditText input=new EditText(this);input.setSingleLine(false);input.setMaxLines(4);input.setMinLines(1);
        input.setTextSize(16);input.setTextColor(FG);input.setHintTextColor(MUTED);input.setHint("Сообщение");
        input.setBackground(shape(PANEL,20));input.setPadding(dp(16),dp(12),dp(12),dp(12));
        composer.addView(input,new LinearLayout.LayoutParams(0,-2,1));
        TextView send=text("↑",28,BG,true);send.setGravity(Gravity.CENTER);send.setBackground(shape(FG,50));
        LinearLayout.LayoutParams p=lp(48,48);p.leftMargin=dp(8);composer.addView(send,p);
        root.addView(composer,lp(-1,-2));
        send.setOnClickListener(v->{
            String content=input.getText().toString().trim();if(content.isEmpty())return;
            call("POST","/chats/"+currentChatId+"/messages",data("body",content),value->{
                input.setText("");loadMessages();
            });
        });
    }
    private void loadMessages() {
        final int chatId=currentChatId;
        if(!screen.equals("conversation"))return;
        call("GET","/chats/"+chatId+"/messages",null,value->{
            if(!screen.equals("conversation") || chatId!=currentChatId)return;
            JSONArray arr=(JSONArray)value;loadedMessages=arr;
            column.removeAllViews();
            if(arr.length()==0)description("Нет сообщений. Начни переписку.");
            for(int i=0;i<arr.length();i++) {
                JSONObject msg=arr.optJSONObject(i);if(msg==null)continue;
                boolean mine=msg.optInt("sender_id")==myUserId;
                LinearLayout row=horizontal();row.setGravity(mine?Gravity.RIGHT:Gravity.LEFT);
                LinearLayout bubble=vertical();pad(bubble,14);
                bubble.setBackground(shape(mine?PANEL2:PANEL,18));
                if(!mine&&currentChat!=null&&"group".equals(str(currentChat,"kind")))
                    bubble.addView(text(str(msg,"sender_name"),12,MUTED,true));
                bubble.addView(text(msg.optInt("deleted")==1?"Сообщение удалено":str(msg,"body"),15,FG,false));
                LinearLayout.LayoutParams bp=lp(-2,-2);bp.width=0;
                TextView time=text(str(msg,"created_at")+ (msg.isNull("edited_at")?"":" · изм."),10,MUTED,false);
                bubble.addView(time,spaced(-2,-2,5));
                JSONArray reactions=msg.optJSONArray("reactions");
                if(reactions!=null&&reactions.length()>0){
                    StringBuilder likes=new StringBuilder();
                    for(int n=0;n<reactions.length();n++){
                        JSONObject reaction=reactions.optJSONObject(n);
                        if(reaction!=null)likes.append(str(reaction,"emoji")).append(" ").append(reaction.optInt("count")).append("  ");
                    }
                    bubble.addView(text(likes.toString(),13,MUTED,false));
                }
                row.addView(bubble,lp(-2,-2));column.addView(row,spaced(-1,-2,8));
                bubble.setOnLongClickListener(v->{messageActions(msg,mine);return true;});
            }
            if(arr.length()>0) {
                int last=arr.optJSONObject(arr.length()-1).optInt("id");
                backend.run("POST","/chats/"+chatId+"/read",data("message_id",last),(v,e)->{});
            }
        });
    }
    private void messageActions(JSONObject msg,boolean mine) {
        if(msg.optInt("deleted")==1)return;
        List<String> actions=new ArrayList<>();
        actions.add("🤍 Реакция");actions.add("👍 Реакция");
        if(mine){actions.add("Редактировать");actions.add("Удалить");}
        new AlertDialog.Builder(this).setTitle("Сообщение").setItems(actions.toArray(new String[0]),(dialog,index)->{
            int id=msg.optInt("id");
            if(index<=1)call("POST","/messages/"+id+"/reactions",data("emoji",index==0?"🤍":"👍"),v->loadMessages());
            else if(index==2) {
                EditText entry=new EditText(this);entry.setText(str(msg,"body"));entry.setTextColor(FG);
                new AlertDialog.Builder(this).setTitle("Редактировать").setView(entry)
                    .setPositiveButton("Сохранить",(d,w)->call("PATCH","/messages/"+id,
                        data("body",entry.getText().toString()),v->loadMessages()))
                    .setNegativeButton("Отмена",null).show();
            } else new AlertDialog.Builder(this).setTitle("Удалить сообщение?")
                .setPositiveButton("Удалить",(d,w)->call("DELETE","/messages/"+id,null,v->loadMessages()))
                .setNegativeButton("Отмена",null).show();
        }).show();
    }
    private void settings() {
        begin("settings",true);
        section("АККАУНТ");
        description("Вход по номеру и паролю. Старые аккаунты можно привязать к номеру, сохранив сообщения.");
        button("Сменить отображаемое имя",false,()->{
            EditText name=new EditText(this);name.setTextColor(FG);
            new AlertDialog.Builder(this).setTitle("Новое имя").setView(name)
                .setPositiveButton("Сохранить",(d,w)->call("PATCH","/me",data("display_name",name.getText().toString()),v->toast("Сохранено")))
                .setNegativeButton("Отмена",null).show();
        });
        button("Привязать номер к старому аккаунту",false,()->linkPhoneDialog());
        button("Настройки поиска по номеру",false,()->visibilityDialog());
        section("ПОДКЛЮЧЕНИЕ");
        description("Текущий сервер: "+backend.server());
        button("Изменить сервер",false,()->serverDialog());
        section("СЕССИЯ");
        button("Выйти",false,()->{backend.logout();authScreen();});
    }
    private void linkPhoneDialog() {
        LinearLayout form=vertical();pad(form,16);
        EditText phone=new EditText(this);phone.setHint("Телефон");phone.setTextColor(FG);phone.setHintTextColor(MUTED);phone.setInputType(InputType.TYPE_CLASS_PHONE);
        EditText password=new EditText(this);password.setHint("Текущий пароль");password.setTextColor(FG);password.setHintTextColor(MUTED);
        password.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);
        form.addView(phone);form.addView(password);
        new AlertDialog.Builder(this).setTitle("Привязать номер").setMessage("Введи пароль существующего аккаунта. SMS-подтверждения нет.")
            .setView(form).setPositiveButton("Привязать",(d,w)->call("POST","/me/phone/link",
                data("phone",phone.getText().toString(),"password",password.getText().toString(),"discoverable",false),v->toast("Номер привязан")))
            .setNegativeButton("Отмена",null).show();
    }
    private void visibilityDialog() {
        call("GET","/me/phone",null,value->{
            JSONObject obj=(JSONObject)value; boolean enabled=obj.optBoolean("discoverable");
            String number=obj.isNull("phone")?"Не привязан":str(obj,"phone");
            new AlertDialog.Builder(this).setTitle("Поиск по номеру")
                .setMessage("Номер: "+number+"\nСейчас: "+(enabled?"разрешён":"выключен")+"\nПо умолчанию номер скрыт.")
                .setPositiveButton(enabled?"Скрыть номер":"Разрешить поиск",(d,w)->
                    call("PATCH","/me/phone/visibility",data("discoverable",!enabled),v->toast("Настройка сохранена")))
                .setNegativeButton("Закрыть",null).show();
        });
    }
    private void serverDialog() {
        EditText input=new EditText(this);input.setText(backend.server());input.setTextColor(FG);
        input.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_URI);
        new AlertDialog.Builder(this).setTitle("HTTPS-сервер").setView(input)
            .setPositiveButton("Сохранить",(d,w)->{
                try {backend.setServer(input.getText().toString().trim());myUserId=0;authScreen();}
                catch(IllegalArgumentException e){toast(e.getMessage());}
            }).setNegativeButton("Отмена",null).show();
    }
}
