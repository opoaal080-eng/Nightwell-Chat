package fun.nightwell.chat;
import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.net.ConnectivityManager;
import android.net.Network;
import android.content.Context;
import android.webkit.*;
import android.widget.*;
import android.view.View;
import java.util.ArrayList;
public final class CallActivity extends Activity {
    private WebView web;
    private PermissionRequest waiting;
    private ConnectivityManager connectivity;
    private ConnectivityManager.NetworkCallback networkCallback;
    private boolean networkLost=false;
    @Override public void onCreate(Bundle b){
        super.onCreate(b);
        getWindow().setStatusBarColor(0xff080808);
        LinearLayout box=new LinearLayout(this); box.setOrientation(1);box.setBackgroundColor(0xff080808);
        Button close=new Button(this);close.setText("Завершить звонок");box.addView(close);
        close.setOnClickListener(v->endCall());
        web=new WebView(this);box.addView(web,new LinearLayout.LayoutParams(-1,0,1));setContentView(box);
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onPermissionRequest(PermissionRequest req){
                runOnUiThread(()->{
                    if(!"https://chat.nightwell.fun".equals(req.getOrigin().toString())){
                        req.deny();return;
                    }
                    ArrayList<String> missing=new ArrayList<>();
                    for(String resource:req.getResources()){
                        if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource) &&
                            checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)
                            missing.add(Manifest.permission.RECORD_AUDIO);
                        if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource) &&
                            checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)
                            missing.add(Manifest.permission.CAMERA);
                    }
                    if(!missing.isEmpty()){
                        waiting=req;
                        requestPermissions(missing.toArray(new String[0]),51);
                    }else grantMedia(req);
                });
            }
        });
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(false);
        web.getSettings().setMediaPlaybackRequiresUserGesture(false);
        web.setWebViewClient(new WebViewClient(){
            @Override public void onPageFinished(WebView view,String url){
                super.onPageFinished(view,url);
                if(url.startsWith("https://chat.nightwell.fun/calls/")&&!ending){
                    view.evaluateJavascript("document.visibilityState",ignored->{});
                }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                String url=request.getUrl().toString();
                return !url.startsWith("https://chat.nightwell.fun/calls/");
            }
            @Override public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error){
                if(request.isForMainFrame()&&!isFinishing()){
                    Toast.makeText(CallActivity.this,"Соединение потеряно. Проверь интернет.",Toast.LENGTH_LONG).show();
                }
            }
        });
        connectivity=(ConnectivityManager)getSystemService(Context.CONNECTIVITY_SERVICE);
        if(android.os.Build.VERSION.SDK_INT>=24 && connectivity!=null){
            networkCallback=new ConnectivityManager.NetworkCallback(){
                @Override public void onLost(Network network){
                    runOnUiThread(()->{
                        if(ending||isFinishing())return;
                        networkLost=true;
                        Toast.makeText(CallActivity.this,"Сеть потеряна. Ожидаем подключение.",Toast.LENGTH_SHORT).show();
                    });
                }
                @Override public void onAvailable(Network network){
                    runOnUiThread(()->{
                        if(!networkLost||ending||isFinishing())return;
                        networkLost=false;
                        Toast.makeText(CallActivity.this,"Сеть восстановлена. Проверяем звонок.",Toast.LENGTH_SHORT).show();
                        if(web!=null)web.evaluateJavascript(
                            "if(typeof pc!=='undefined' && pc && pc.connectionState==='failed' && typeof restartIce==='function')restartIce();",
                            ignored->{});
                    });
                }
            };
            connectivity.registerDefaultNetworkCallback(networkCallback);
        }
        String u=getIntent().getStringExtra("url");
        if(u!=null && u.startsWith("https://chat.nightwell.fun/calls/"))web.loadUrl(u);else finish();
    }
    private void grantMedia(PermissionRequest req){
        ArrayList<String> allowed=new ArrayList<>();
        for(String resource:req.getResources()){
            if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource) &&
                checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)
                allowed.add(resource);
            if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource) &&
                checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)
                allowed.add(resource);
        }
        if(allowed.isEmpty())req.deny();
        else req.grant(allowed.toArray(new String[0]));
    }
    @Override public void onRequestPermissionsResult(int req,String[] p,int[] granted){
        super.onRequestPermissionsResult(req,p,granted);
        if(req==51 && waiting!=null){grantMedia(waiting);waiting=null;}
    }
    private boolean ending=false;
    private void endCall(){
        if(ending)return;
        ending=true;
        if(web!=null){
            web.postDelayed(this::finish,1200);
            web.evaluateJavascript("if(typeof closeCall==='function')closeCall();",ignored->finish());
        }else finish();
    }
    @Override public void onBackPressed(){endCall();}
    @Override public void onDestroy(){if(connectivity!=null&&networkCallback!=null)connectivity.unregisterNetworkCallback(networkCallback);if(waiting!=null)waiting.deny();if(web!=null){web.loadUrl("about:blank");web.destroy();}super.onDestroy();}
}
