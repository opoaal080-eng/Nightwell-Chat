package fun.nightwell.chat;
import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.content.Context;
import android.webkit.*;
import android.widget.*;
import android.view.View;
import java.util.ArrayList;
public final class CallActivity extends Activity {
    private WebView web;
    private TextView status;
    private Button retry;
    private PermissionRequest waiting;
    private ConnectivityManager connectivity;
    private ConnectivityManager.NetworkCallback networkCallback;
    private boolean networkLost=false;
    private Uri allowedCallUri;
    @Override public void onCreate(Bundle b){
        super.onCreate(b);
        String target=getIntent().getStringExtra("url");
        try{allowedCallUri=Uri.parse(target==null?"":target);}catch(Exception ignored){finish();return;}
        if(!"https".equalsIgnoreCase(allowedCallUri.getScheme())||allowedCallUri.getHost()==null||
            allowedCallUri.getPath()==null||!allowedCallUri.getPath().matches("/calls/[0-9a-f]{32}/page")||
            allowedCallUri.getFragment()==null||!allowedCallUri.getFragment().startsWith("ticket=")){
            finish();return;
        }
        getWindow().setStatusBarColor(0xff080808);
        LinearLayout box=new LinearLayout(this); box.setOrientation(1);box.setBackgroundColor(0xff080808);
        Button close=new Button(this);close.setText("Завершить звонок");box.addView(close);
        close.setOnClickListener(v->endCall());
        status=new TextView(this);status.setTextColor(-1);status.setText("Открываем звонок…");box.addView(status);
        retry=new Button(this);retry.setText("Повторить");retry.setVisibility(View.GONE);box.addView(retry);
        retry.setOnClickListener(v->{retry.setVisibility(View.GONE);status.setText("Загрузка…");web.reload();});
        web=new WebView(this);web.setBackgroundColor(0xff080808);box.addView(web,new LinearLayout.LayoutParams(-1,0,1));setContentView(box);
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onPermissionRequest(PermissionRequest req){
                runOnUiThread(()->{
                    if(!sameOrigin(req.getOrigin())){
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
            @Override public void onReceivedHttpError(WebView view,WebResourceRequest request,WebResourceResponse response){if(request.isForMainFrame())showError("Сервер не открыл звонок: HTTP "+response.getStatusCode());}
            @Override public void onPageFinished(WebView view,String url){
                super.onPageFinished(view,url);
                if(sameCallOrigin(Uri.parse(url))&&!ending){
                    view.evaluateJavascript("Boolean(document.getElementById('start') && document.getElementById('state'))",result->{
                        if("true".equals(result)){status.setVisibility(View.GONE);retry.setVisibility(View.GONE);}
                        else showError("Сервер вернул другую страницу вместо звонка");
                    });
                }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                return !sameCallOrigin(request.getUrl());
            }
            @Override public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error){
                if(request.isForMainFrame()&&!isFinishing()){
                    showError("Не удалось загрузить звонок. Проверь интернет.");
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
                            "if(typeof restartIce==='function')restartIce();",
                            ignored->{});
                    });
                }
            };
            connectivity.registerDefaultNetworkCallback(networkCallback);
        }
        web.loadUrl(allowedCallUri.toString());
    }
    private boolean sameOrigin(Uri uri){
        return uri!=null && allowedCallUri!=null && "https".equalsIgnoreCase(uri.getScheme()) &&
            allowedCallUri.getHost().equalsIgnoreCase(uri.getHost()) && allowedCallUri.getPort()==uri.getPort();
    }
    private boolean sameCallOrigin(Uri uri){
        return sameOrigin(uri) && uri.getPath()!=null && uri.getPath().startsWith("/calls/");
    }
    private void showError(String text){status.setVisibility(View.VISIBLE);status.setText(text);retry.setVisibility(View.VISIBLE);}
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
