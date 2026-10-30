package fun.nightwell.chat;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

final class Backend {
    interface Result { void done(Object value, String error); }
    interface Event { void changed(); }
    private static final String ALIAS = "NightwellChatSession";
    private final Context context;
    private final OkHttpClient http = new OkHttpClient.Builder().retryOnConnectionFailure(true).build();
    private final ExecutorService queue = Executors.newFixedThreadPool(3);
    private final SharedPreferences prefs;
    private String token = "";
    private String server;
    private WebSocket socket;
    private Event listener;

    Backend(Context context) {
        this.context = context.getApplicationContext();
        prefs = this.context.getSharedPreferences("nw.chat.settings", Context.MODE_PRIVATE);
        server = prefs.getString("server", "https://chat.nightwell.fun");
        token = unseal(prefs.getString("session", ""));
    }
    synchronized boolean signedIn() { return !token.isEmpty(); }
    synchronized String server() { return server; }
    synchronized void setServer(String value) {
        if (!value.matches("https://[^/\\s?#]+(?::[0-9]{2,5})?/?")) throw new IllegalArgumentException("Нужен HTTPS-адрес сервера");
        closeSocket();
        token="";
        server=value.replaceAll("/$", "");
        prefs.edit().putString("server",server).remove("session").apply();
    }
    synchronized void accept(JSONObject auth) throws JSONException {
        token=auth.getString("access_token");
        prefs.edit().putString("session",seal(token)).apply();
    }
    synchronized void logout() {
        closeSocket();
        token="";
        prefs.edit().remove("session").apply();
    }
    void run(String verb, String endpoint, JSONObject data, Result callback) {
        queue.execute(() -> {
            try {
                String base; String session;
                synchronized (this) { base=server; session=token; }
                String url=base+endpoint;
                Request.Builder builder = new Request.Builder().url(url).header("Accept", "application/json");
                if (!session.isEmpty()) builder.header("Authorization", "Bearer "+session);
                RequestBody body = data==null ? RequestBody.create("", MediaType.parse("application/json")) : RequestBody.create(data.toString(), MediaType.parse("application/json"));
                if (verb.equals("GET")) builder.get();
                else if (verb.equals("DELETE")) builder.delete();
                else builder.method(verb,body);
                try (Response r=http.newCall(builder.build()).execute()) {
                    String text=r.body()==null ? "" : r.body().string();
                    Object object;
                    if(text.isEmpty()) object=new JSONObject();
                    else if(text.trim().startsWith("[")) object=new JSONArray(text);
                    else if(text.trim().equals("null")) object=JSONObject.NULL;
                    else object=new JSONObject(text);
                    if(!r.isSuccessful()) {
                        String detail=object instanceof JSONObject ? ((JSONObject)object).optString("detail","HTTP "+r.code()) : "HTTP "+r.code();
                        callback.done(null,detail);
                    } else callback.done(object,null);
                }
            } catch (Exception ex) { callback.done(null, ex.getMessage()==null?"Сбой сети":ex.getMessage()); }
        });
    }
    synchronized void watch(Event callback) {
        closeSocket();
        listener=callback;
        if(token.isEmpty()) return;
        Request req = new Request.Builder().url(server.replaceFirst("^https:","wss:")+"/ws")
            .header("Authorization","Bearer "+token).build();
        socket=http.newWebSocket(req,new WebSocketListener() {
            @Override public void onMessage(WebSocket ws,String message) {
                if(message.contains("\"type\"")) {
                    Event event;
                    synchronized (Backend.this) { event=listener; }
                    if(event != null) event.changed();
                }
            }
            @Override public void onFailure(WebSocket ws,Throwable error,Response resp) { /* refresh also works manually */ }
        });
    }
    private synchronized void closeSocket() {
        listener=null;
        if(socket!=null) socket.close(1000,"close");
        socket=null;
    }
    private static SecretKey key() throws Exception {
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        if(!ks.containsAlias(ALIAS)) {
            KeyGenerator gen=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
            gen.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
              .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            gen.generateKey();
        }
        return ((KeyStore.SecretKeyEntry)ks.getEntry(ALIAS,null)).getSecretKey();
    }
    private static String seal(String value) {
        try {
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE,key());
            byte[] iv=cipher.getIV(), encrypted=cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
            byte[] output=new byte[iv.length+encrypted.length];
            System.arraycopy(iv,0,output,0,iv.length);
            System.arraycopy(encrypted,0,output,iv.length,encrypted.length);
            return Base64.encodeToString(output,Base64.NO_WRAP);
        } catch(Exception e) { throw new IllegalStateException("Невозможно сохранить сессию",e); }
    }
    private static String unseal(String value) {
        if(value.isEmpty()) return "";
        try {
            byte[] data=Base64.decode(value,Base64.NO_WRAP);
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,data,0,12));
            return new String(cipher.doFinal(data,12,data.length-12),StandardCharsets.UTF_8);
        } catch(Exception e) { return ""; }
    }
}
