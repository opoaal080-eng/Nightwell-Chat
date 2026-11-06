package fun.nightwell.chat;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.PictureInPictureParams;
import android.content.Intent;
import android.content.res.Configuration;
import android.media.AudioDeviceInfo;
import android.os.Build;
import android.util.Rational;
import java.lang.ref.WeakReference;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.media.AudioManager;
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
    private Button micButton, endButton, retry, routeButton, minimizeButton;
    private TextView avatar, title;
    private LinearLayout controls;
    private static WeakReference<CallActivity> current = new WeakReference<>(null);
    static boolean isRunning() {
        CallActivity activity = current.get();
        return activity != null && !activity.ending;
    }

    private PermissionRequest waiting;
    private ConnectivityManager connectivity;
    private AudioManager audioManager;
    private int previousAudioMode=AudioManager.MODE_NORMAL;
    private boolean changedAudioMode=false;
    private ConnectivityManager.NetworkCallback networkCallback;
    private Uri callUri;
    private boolean networkLost=false, ending=false, muted=false, webReady=false, micAsked=false, startIssued=false, microphoneFailure=false, connectionFailure=false;

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
        current = new WeakReference<>(this);
        String target=getIntent().getStringExtra("url");
        try{callUri=Uri.parse(target==null?"":target);}catch(Exception exception){finish();return;}
        if(!"https".equalsIgnoreCase(callUri.getScheme()) || callUri.getHost()==null ||
            callUri.getPath()==null || !callUri.getPath().matches("/calls/[0-9a-f]{32}/page") ||
            callUri.getFragment()==null || !callUri.getFragment().startsWith("ticket=")){
            finish();return;
        }
        getWindow().setStatusBarColor(Color.BLACK);
        getWindow().setNavigationBarColor(Color.BLACK);
        // Configure the native audio route for WebRTC on physical Android phones.
        audioManager=(AudioManager)getSystemService(Context.AUDIO_SERVICE);
        if(audioManager!=null){
            try{
                previousAudioMode=audioManager.getMode();
                if(previousAudioMode!=AudioManager.MODE_IN_COMMUNICATION){
                    audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
                    changedAudioMode=true;
                }
            }catch(SecurityException exception){
                android.util.Log.w("NightwellCall","Cannot set voice communication mode",exception);
            }
        }

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

        minimizeButton=new Button(this);
        minimizeButton.setText("⌄ Скрыть звонок");
        minimizeButton.setAllCaps(false);
        minimizeButton.setTextSize(14);
        minimizeButton.setTextColor(Color.WHITE);
        minimizeButton.setBackgroundColor(0xff19191d);
        screen.addView(minimizeButton,sized(-1,44));
        minimizeButton.setOnClickListener(v->minimizeCall());
        title=text("N I G H T W E L L   C H A T",13,0xffaaaaaa);
        screen.addView(title,sized(-1,48));
        View space1=new View(this);
        screen.addView(space1,new LinearLayout.LayoutParams(1,0,1));
        avatar=text("☎",75,Color.WHITE);
        avatar.setBackground(circle(0xff2b2b31));
        screen.addView(avatar,sized(132,132));
        TextView heading=text("Голосовой звонок",27,Color.WHITE);
        LinearLayout.LayoutParams headingParams=sized(-1,66);
        headingParams.topMargin=dp(18);
        screen.addView(heading,headingParams);
        status=text("Подключаем…",16,0xffb8b8b8);
        status.setPadding(dp(16),dp(4),dp(16),dp(12));
        status.setMinHeight(dp(84));
        status.setMaxLines(6);
        screen.addView(status,sized(-1,-2));
        retry=new Button(this);
        retry.setText("Повторить");
        retry.setAllCaps(false);
        retry.setVisibility(View.GONE);
        screen.addView(retry,sized(150,52));
        retry.setOnClickListener(v->{
            retry.setVisibility(View.GONE);
            connectionFailure=false;
            status.setText("Проверяем микрофон…");
            if(microphoneFailure && webReady){
                microphoneFailure=false;
                startIssued=false;
                tryStartAudio();
            } else {
                webReady=false;startIssued=false;
                web.reload();
            }
        });
        View space2=new View(this);
        screen.addView(space2,new LinearLayout.LayoutParams(1,0,1));

        controls=new LinearLayout(this);
        controls.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams controlsParams=sized(-1,116);
        screen.addView(controls,controlsParams);
        micButton=new Button(this);
        micButton.setText("🎙 Микрофон");
        micButton.setTextColor(Color.WHITE);
        micButton.setTextSize(15);
        micButton.setAllCaps(false);
        micButton.setBackground(circle(0xff303036));
        LinearLayout.LayoutParams micParams=sized(92,76);
        micParams.setMargins(dp(4),0,dp(4),0);
        controls.addView(micButton,micParams);
        micButton.setEnabled(false);
        micButton.setOnClickListener(v->{
            muted=!muted;
            web.evaluateJavascript("window.setCallMuted && window.setCallMuted("+muted+");",null);
            micButton.setText(muted?"🎙 Включить":"🎙 Микрофон");
        });
        routeButton=new Button(this);
        routeButton.setText("🔊 Вывод");
        routeButton.setTextColor(Color.WHITE);
        routeButton.setTextSize(14);
        routeButton.setAllCaps(false);
        routeButton.setBackground(circle(0xff303036));
        LinearLayout.LayoutParams routeParams=sized(92,76);
        routeParams.setMargins(dp(4),0,dp(4),0);
        controls.addView(routeButton,routeParams);
        routeButton.setOnClickListener(v->showAudioRoutes());
        endButton=new Button(this);
        endButton.setText("Завершить");
        endButton.setTextSize(15);
        endButton.setTextColor(Color.WHITE);
        endButton.setAllCaps(false);
        endButton.setBackground(circle(0xffd83e50));
        LinearLayout.LayoutParams endParams=sized(112,76);
        endParams.setMargins(dp(4),0,dp(4),0);
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
                if(!sameCallOrigin(Uri.parse(address))||ending||connectionFailure)return;
                view.evaluateJavascript(
                    "Boolean(document.getElementById('start')&&window.startCallAudio&&window.NIGHTWELL_CALL_PAGE_VERSION)",
                    result->{
                        if("true".equals(result)){
                            retry.setVisibility(View.GONE);
                            microphoneFailure=false;connectionFailure=false;webReady=true;tryStartAudio();
                        }else showError("Устаревшая страница звонка на сервере. Обнови файлы server/app.py и server/call_page.html и перезапусти Nightwell Chat.");
                    }
                );
            }
            @Override public void onReceivedHttpError(WebView view,WebResourceRequest request,WebResourceResponse response){
                if(request.isForMainFrame())showError("Сервер не открыл звонок: HTTP "+response.getStatusCode());
            }
            @Override public void onReceivedError(WebView view,WebResourceRequest request,android.webkit.WebResourceError error){
                if(!request.isForMainFrame()||ending)return;
                connectionFailure=true;
                if(error.getErrorCode()==WebViewClient.ERROR_HOST_LOOKUP){
                    showError("DNS не находит chat.nightwell.fun. Проверь DNS-запись домена, затем Wi-Fi или мобильный интернет.");
                }else showError("Не удалось загрузить звонок. Проверь интернет и HTTPS сервера.");
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
        CallForegroundService.begin(this);
        if(Build.VERSION.SDK_INT>=31)
            setPictureInPictureParams(new PictureInPictureParams.Builder()
                .setAspectRatio(new Rational(1,1)).setAutoEnterEnabled(true).build());
        // Do not enable mute until WebRTC confirms that the input source has started.
        micButton.setEnabled(false);
        web.evaluateJavascript("if(window.startCallAudio){void window.startCallAudio();true}else false",null);
    }

    private void minimizeCall() {
        if(ending || !webReady || checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(this,"Дождись подключения звонка",Toast.LENGTH_SHORT).show();
            return;
        }
        if(Build.VERSION.SDK_INT>=26) {
            try {
                enterPictureInPictureMode(new PictureInPictureParams.Builder()
                    .setAspectRatio(new Rational(1,1)).build());
            } catch (RuntimeException e) {
                android.util.Log.w("NightwellCall","Picture-in-picture unavailable",e);
                Toast.makeText(this,"Режим мини-окна недоступен на устройстве",Toast.LENGTH_LONG).show();
            }
        }
    }

    @Override public void onUserLeaveHint() {
        super.onUserLeaveHint();
        if(Build.VERSION.SDK_INT>=26 && Build.VERSION.SDK_INT<31 && webReady && !ending)
            minimizeCall();
    }

    @Override public void onPictureInPictureModeChanged(boolean inPip, Configuration config) {
        super.onPictureInPictureModeChanged(inPip,config);
        if(minimizeButton!=null)minimizeButton.setVisibility(inPip?View.GONE:View.VISIBLE);
        if(title!=null)title.setVisibility(inPip?View.GONE:View.VISIBLE);
        if(avatar!=null)avatar.setVisibility(inPip?View.GONE:View.VISIBLE);
        if(controls!=null)controls.setVisibility(inPip?View.GONE:View.VISIBLE);
    }

    private void showAudioRoutes() {
        if(audioManager==null)return;
        if(Build.VERSION.SDK_INT>=31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT},52);
            return;
        }
        ArrayList<String> labels=new ArrayList<>();
        ArrayList<Runnable> routes=new ArrayList<>();
        if(Build.VERSION.SDK_INT>=31) {
            for(AudioDeviceInfo device:audioManager.getAvailableCommunicationDevices()) {
                String name=audioDeviceLabel(device);
                if(name==null)continue;
                labels.add(name);
                routes.add(()->{
                    boolean ok=audioManager.setCommunicationDevice(device);
                    if(!ok)Toast.makeText(this,"Не удалось переключить устройство",Toast.LENGTH_SHORT).show();
                });
            }
        } else {
            labels.add("Разговорный динамик");
            routes.add(()->{audioManager.setBluetoothScoOn(false);audioManager.stopBluetoothSco();audioManager.setSpeakerphoneOn(false);});
            labels.add("Громкая связь");
            routes.add(()->{audioManager.setBluetoothScoOn(false);audioManager.stopBluetoothSco();audioManager.setSpeakerphoneOn(true);});
            for(AudioDeviceInfo device:audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                int type=device.getType();
                if(type==AudioDeviceInfo.TYPE_WIRED_HEADSET || type==AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                   type==AudioDeviceInfo.TYPE_USB_HEADSET) {
                    labels.add("Подключённые наушники");
                    routes.add(()->{audioManager.setBluetoothScoOn(false);audioManager.stopBluetoothSco();audioManager.setSpeakerphoneOn(false);});
                    break;
                }
                if(type==AudioDeviceInfo.TYPE_BLUETOOTH_SCO && audioManager.isBluetoothScoAvailableOffCall()) {
                    labels.add("Bluetooth-гарнитура");
                    routes.add(()->{audioManager.setSpeakerphoneOn(false);audioManager.startBluetoothSco();audioManager.setBluetoothScoOn(true);});
                }
            }
        }
        if(labels.isEmpty()){Toast.makeText(this,"Нет доступных аудиоустройств",Toast.LENGTH_SHORT).show();return;}
        new AlertDialog.Builder(this).setTitle("Устройство вывода")
            .setItems(labels.toArray(new String[0]),(dialog,index)->routes.get(index).run())
            .setNegativeButton("Отмена",null).show();
    }

    private String audioDeviceLabel(AudioDeviceInfo device) {
        switch(device.getType()) {
            case AudioDeviceInfo.TYPE_BUILTIN_EARPIECE:return "Разговорный динамик";
            case AudioDeviceInfo.TYPE_BUILTIN_SPEAKER:return "Громкая связь";
            case AudioDeviceInfo.TYPE_WIRED_HEADSET:
            case AudioDeviceInfo.TYPE_WIRED_HEADPHONES:return "Проводные наушники";
            case AudioDeviceInfo.TYPE_BLUETOOTH_SCO:return "Bluetooth · "+device.getProductName();
            case AudioDeviceInfo.TYPE_BLE_HEADSET:return "Bluetooth LE · "+device.getProductName();
            case AudioDeviceInfo.TYPE_USB_HEADSET:return "USB · "+device.getProductName();
            case AudioDeviceInfo.TYPE_HEARING_AID:return "Слуховой аппарат";
            default:return null;
        }
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
        if(request==52) {
            showAudioRoutesIfAllowed();
            return;
        }
        if(request==MIC_REQUEST){
            if(waiting!=null){grantAudio(waiting);waiting=null;}
            if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)
                tryStartAudio();
            else showError("Разреши микрофон Nightwell Chat в настройках Android");
        }
    }
    private void showAudioRoutesIfAllowed() {
        // Even when Bluetooth permission is declined, internal routes remain usable.
        if(Build.VERSION.SDK_INT<31 ||
           checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED)
            showAudioRoutes();
        else new AlertDialog.Builder(this).setTitle("Вывод звука")
            .setItems(new String[]{"Разговорный динамик","Громкая связь"},(dialog,which)->{
                if(audioManager==null)return;
                for(AudioDeviceInfo device:audioManager.getAvailableCommunicationDevices()) {
                    if(device.getType()==(which==0?AudioDeviceInfo.TYPE_BUILTIN_EARPIECE:AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)) {
                        audioManager.setCommunicationDevice(device);
                        return;
                    }
                }
            }).show();
    }
    private final class NativeBridge {
        @JavascriptInterface public void postMessage(String json){
            try {
                JSONObject event=new JSONObject(json);
                String type=event.optString("type","");
                String message=event.optString("message","");
                String code=event.optString("code","");
                // Older servers described phone microphone failures as BlueStacks errors.
                // Never display emulator instructions on a physical Android handset.
                String visibleMessage=message;
                if("microphone_error".equals(type) &&
                   ("NotReadableError".equals(code)||"TrackStartError".equals(code)||
                    "AbortError".equals(code)||message.contains("BlueStacks"))){
                    visibleMessage="Android не смог открыть микрофон. Разреши доступ для Nightwell Chat, проверь системный переключатель микрофона и закрой другие звонки. После этого нажми «Повторить».";
                }
                final String shownMessage=visibleMessage;
                runOnUiThread(()->{
                    if(ending)return;
                    if("ended".equals(type)){ending=true;finish();}
                    else if("microphone_ready".equals(type)){
                        microphoneFailure=false;
                        micButton.setEnabled(true);
                        retry.setVisibility(View.GONE);
                    }
                    else if("microphone_error".equals(type)){
                        android.util.Log.w("NightwellCall","WebRTC microphone: "+event.optString("code","unknown"));
                        startIssued=false;
                        microphoneFailure=true;
                        micButton.setEnabled(false);
                        showError(shownMessage);
                    }
                    else if("call_error".equals(type)){
                        connectionFailure=true;
                        android.util.Log.w("NightwellCall","WebRTC ICE timeout: "+event.optString("code","unknown"));
                        showError(message);
                    }
                    else if("state".equals(type)){
                        if("Разговор".equals(message)){
                            connectionFailure=false;
                            retry.setVisibility(View.GONE);
                        }
                        if(!microphoneFailure && !connectionFailure)status.setText(message);
                    }
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
        CallForegroundService.finish(this);
        if(web!=null){
            web.postDelayed(this::finish,800);
            web.evaluateJavascript("if(typeof closeCall === 'function')closeCall();",ignored->finish());
        }else finish();
    }
    @Override public void onBackPressed(){minimizeCall();}
    @Override protected void onDestroy(){
        if(current.get()==this)current=new WeakReference<>(null);
        CallForegroundService.finish(this);
        if(changedAudioMode&&audioManager!=null){
            try{audioManager.setMode(previousAudioMode);}
            catch(SecurityException exception){android.util.Log.w("NightwellCall","Audio mode restore failed",exception);}
        }
        if(connectivity!=null&&networkCallback!=null)connectivity.unregisterNetworkCallback(networkCallback);
        if(waiting!=null)waiting.deny();
        if(web!=null){web.loadUrl("about:blank");web.removeJavascriptInterface("NightwellBridge");web.destroy();}
        super.onDestroy();
    }
}
