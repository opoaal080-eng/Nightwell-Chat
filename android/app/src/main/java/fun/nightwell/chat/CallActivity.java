package fun.nightwell.chat;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONObject;
import java.util.ArrayList;

public final class CallActivity extends Activity {
    private static final int MIC_REQUEST = 51;
    private WebView web;
    private TextView status;
    private Button micButton, endButton, retry;
    private PermissionRequest waiting;
    private ConnectivityManager connectivity;
    private ConnectivityManager.NetworkCallback networkCallback;
    private Uri callUri;
    private boolean networkLost=false, ending=false, muted=false, webReady=false, micAsked=false, startIssued=false;

    private int dp(int value){return (int)(value*getResources().getDisplayMetrics().density);}
    private GradientDrawable circle(int color){
        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.OVAL);
        drawable.setColor(color);
        return drawable;
    }
    private TextView text(String value,int size,int color){
        TextView label=new TextView(this);
        label.setText(value);label.setTextSize(size);label.setTextColor(color);
        label.setGravity(Gravity.CENTER);
        return label;
    }
    private LinearLayout.LayoutParams sized(int width,int height){
        return new LinearLayout.LayoutParams(width<0?width:dp(width),height<0?height:dp(height));
    }
    @Override public void onCreate(Bundle bundle){
        super.onCreate(bundle);
        String target=getIntent().getStringExtra("url");
        try{callUri=Uri.parse(target==null?"":target);}catch(Exception exception){finish();return;}
        if(!"https".equalsIgnoreCase(callUri.getScheme()) || callUri.getHost()==null ||
            callUri.getPath()==null || !callUri.getPath().matches("/calls/[0-9a-f]{32}/page") ||
            callUri.getFragment()==null || !callUri.getFragment().startsWith("ticket=")){
            finish();return;
        }
        getWindow().setStatusBarColor(Color.BLACK);
        getWindow().setNavigationBarColor(Color.BLACK);

        FrameLayout root=new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        web=new WebView(this);
        web.setBackgroundColor(Color.BLACK);
        web.setAlpha(0.015f);
        FrameLayout.LayoutParams transport=new FrameLayout.LayoutParams(dp(240),dp(180),Gravity.CENTER);
        root.addView(web,transport);

        LinearLayout screen=new LinearLayout(this);
        screen.setOrientation(LinearLayout.VERTICAL);
        screen.setGravity(Gravity.CENTER_HORIZONTAL);
        screen.setPadding(dp(18),dp(36),dp(18),dp(32));
        FrameLayout.LayoutParams full=new FrameLayout.LayoutParams(-1,-1);
        root.addView(screen,full);

        TextView title=text("N I G H T W E L L   C H A T",13,0xffaaaaaa);
        screen.addView(title,sized(-1,48));
        View space1=new View(this);
        screen.addView(space1,new LinearLayout.LayoutParams(1,0,1));
        TextView avatar=text("☎",75,Color.WHITE);
        avatar.setBackground(circle(0xff2b2b31));
        screen.addView(avatar,sized(132,132));
        TextView heading=text("Голосовой звонок",27,Color.WHITE);
        LinearLayout.LayoutParams headingParams=sized(-1,66);
        headingParams.topMargin=dp(18);
        screen.addView(heading,headingParams);
        status=text("Подключаем…",16,0xffb8b8b8);
        status.setPadding(dp(16),dp(4),dp(16),dp(12));
        screen.addView(status,sized(-1,84));
        retry=new Button(this);
        retry.setText("Повторить");
        retry.setAllCaps(false);
        retry.setVisibility(View.GONE);
        screen.addView(retry,sized(150,52));
        retry.setOnClickListener(v->{
            retry.setVisibility(View.GONE);
            status.setText("Подключаем…");
            webReady=false;startIssued=false;web.reload();
        });
        View space2=new View(this);
        screen.addView(space2,new LinearLayout.LayoutParams(1,0,1));

        LinearLayout controls=new LinearLayout(this);
        controls.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams controlsParams=sized(-1,116);
        screen.addView(controls,controlsParams);
        micButton=new Button(this);
        micButton.setText("🎙 Микрофон");
        micButton.setTextColor(Color.WHITE);
        micButton.setTextSize(15);
        micButton.setAllCaps(false);
        micButton.setBackground(circle(0xff303036));
        LinearLayout.LayoutParams micParams=sized(126,76);
        micParams.setMargins(dp(10),0,dp(10),0);
        controls.addView(micButton,micParams);
        micButton.setEnabled(false);
        micButton.setOnClickListener(v->{
            muted=!muted;
            web.evaluateJavascript("window.setCallMuted && window.setCallMuted("+muted+");",null);
            micButton.setText(muted?"🎙 Включить":"🎙 Микрофон");
        });
        endButton=new Button(this);
        endButton.setText("Завершить");
        endButton.setTextSize(15);
        endButton.setTextColor(Color.WHITE);
        endButton.setAllCaps(false);
        endButton.setBackground(circle(0xffd83e50));
        LinearLayout.LayoutParams endParams=sized(126,76);
        endParams.setMargins(dp(10),0,dp(10),0);
        controls.addView(endButton,endParams);
        endButton.setOnClickListener(v->endCall());
        setContentView(root);

        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(false);
        web.getSettings().setMediaPlaybackRequiresUserGesture(false);
        web.getSettings().setSupportZoom(false);
        web.getSettings().setBuiltInZoomControls(false);
        web.getSettings().setDisplayZoomControls(false);
        web.getSettings().setUseWideViewPort(false);
        web.addJavascriptInterface(new NativeBridge(),"NightwellBridge");
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onPermissionRequest(PermissionRequest permission){
                runOnUiThread(()->{
                    if(!sameOrigin(permission.getOrigin())){permission.deny();return;}
                    ArrayList<String> missing=new ArrayList<>();
                    for(String resource:permission.getResources()){
                        if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource) &&
                           checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)
                            missing.add(Manifest.permission.RECORD_AUDIO);
                    }
                    if(missing.isEmpty())grantAudio(permission);
                    else if(!micAsked){
                        micAsked=true;
                        waiting=permission;
                        requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO},MIC_REQUEST);
                    }else {
                        permission.deny();
                        showError("Открой настройки Android и разреши Nightwell Chat доступ к микрофону");
                    }
                });
            }
        });
        web.setWebViewClient(new WebViewClient(){
            @Override public void onPageFinished(WebView view,String address){
                if(!sameCallOrigin(Uri.parse(address))||ending)return;
                view.evaluateJavascript(
                    "Boolean(document.getElementById('start')&&window.startCallAudio)",
                    result->{
                        if("true".equals(result)){
                            retry.setVisibility(View.GONE);
                            webReady=true;tryStartAudio();
                        }else showError("Сервер вернул старую страницу звонка. Обнови сервер.");
                    }
                );
            }
            @Override public void onReceivedHttpError(WebView view,WebResourceRequest request,WebResourceResponse response){
                if(request.isForMainFrame())showError("Сервер не открыл звонок: HTTP "+response.getStatusCode());
            }
            @Override public void onReceivedError(WebView view,WebResourceRequest request,android.webkit.WebResourceError error){
                if(request.isForMainFrame()&&!ending)showError("Не удалось загрузить звонок. Проверь соединение.");
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                return !sameCallOrigin(request.getUrl());
            }
        });
        connectivity=(ConnectivityManager)getSystemService(Context.CONNECTIVITY_SERVICE);
        if(connectivity!=null){
            networkCallback=new ConnectivityManager.NetworkCallback(){
                @Override public void onLost(Network network){runOnUiThread(()->networkLost=true);}
                @Override public void onAvailable(Network network){
                    runOnUiThread(()->{
                        if(networkLost&&!ending&&web!=null){
                            networkLost=false;
                            status.setText("Восстанавливаем соединение…");
                            web.evaluateJavascript("window.restartIce && window.restartIce();",null);
                        }
                    });
                }
            };
            connectivity.registerDefaultNetworkCallback(networkCallback);
        }
        if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){
            micAsked=true;
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO},MIC_REQUEST);
        }
        web.loadUrl(callUri.toString());
    }
    private void tryStartAudio(){
        if(ending||!webReady||startIssued||web==null)return;
        if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)return;
        startIssued=true;
        micButton.setEnabled(true);
        web.evaluateJavascript("window.startCallAudio && window.startCallAudio();",null);
    }
    private boolean sameOrigin(Uri uri){
        return uri!=null && callUri!=null && "https".equalsIgnoreCase(uri.getScheme()) &&
            callUri.getHost().equalsIgnoreCase(uri.getHost()) && callUri.getPort()==uri.getPort();
    }
    private boolean sameCallOrigin(Uri uri){
        return sameOrigin(uri) && uri.getPath()!=null && uri.getPath().startsWith("/calls/");
    }
    private void showError(String message){
        if(ending)return;
        status.setText(message);
        retry.setVisibility(View.VISIBLE);
    }
    private void grantAudio(PermissionRequest req){
        ArrayList<String> allowed=new ArrayList<>();
        for(String resource:req.getResources()){
            if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource) &&
                checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED){
                allowed.add(resource);
            }
        }
        if(allowed.isEmpty())req.deny();
        else req.grant(allowed.toArray(new String[0]));
    }
    @Override public void onRequestPermissionsResult(int request,String[] perms,int[] granted){
        super.onRequestPermissionsResult(request,perms,granted);
        if(request==MIC_REQUEST){
            if(waiting!=null){grantAudio(waiting);waiting=null;}
            if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)
                tryStartAudio();
            else showError("Разреши микрофон Nightwell Chat в настройках Android");
        }
    }
    private final class NativeBridge {
        @JavascriptInterface public void postMessage(String json){
            try {
                JSONObject event=new JSONObject(json);
                String type=event.optString("type","");
                String message=event.optString("message","");
                runOnUiThread(()->{
                    if(ending)return;
                    if("ended".equals(type)){ending=true;finish();}
                    else if("state".equals(type)){status.setText(message);}
                    else if("mute".equals(type)){
                        muted="on".equals(message);
                        micButton.setText(muted?"🎙 Включить":"🎙 Микрофон");
                    }
                });
            }catch(Exception ignored){}
        }
    }
    private void endCall(){
        if(ending)return;
        ending=true;
        endButton.setEnabled(false);
        if(web!=null){
            web.postDelayed(this::finish,800);
            web.evaluateJavascript("if(typeof closeCall === 'function')closeCall();",ignored->finish());
        }else finish();
    }
    @Override public void onBackPressed(){endCall();}
    @Override protected void onDestroy(){
        if(connectivity!=null&&networkCallback!=null)connectivity.unregisterNetworkCallback(networkCallback);
        if(waiting!=null)waiting.deny();
        if(web!=null){web.loadUrl("about:blank");web.removeJavascriptInterface("NightwellBridge");web.destroy();}
        super.onDestroy();
    }
}
