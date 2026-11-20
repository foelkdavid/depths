module depths;
import std::math;
import std::io;
import raylib6::rl;
import vpt;
import vpt::ui;

// DEPTHS: the game without the editor (build target vpt-game). A main menu over a live diorama (the robot on
// the ash waste under the galaxy, looking at the mouse), settings, then a run: always a generated, detailed
// layer 0 (optional seed), descending through the rifts. Shares src/ with the editor (target vpt-engine).

const ZString ESC_TARGET="main menu";   // game HUD hint after death
fn void after_generated() { }           // play_generated hook (the editor reframes / forgets its file here)

bool dbg_menu=false;bool run_test;int test_step;int test_frames;
const uint MENU_SEED=1101;              // the diorama behind the menu
const int APP_MENU=0;const int APP_GAME=1;
const int PANEL_MAIN=0;const int PANEL_START=1;const int PANEL_SETTINGS=2;const int PANEL_BESTIARY=3;
const int JOB_NONE=0;const int JOB_MENU=1;const int JOB_RUN=2;
int app_state;int panel;bool paused;int pause_panel;
int job;int job_wait;ZString job_text;   // generation runs one frame after its loading screen was shown
char[12] seed_text;int seed_len;bool seed_focus=true;
int menu_robot= -1;Vec menu_at;Vec menu_f;Vec menu_right;   // frozen frame: the robot's spot and facing when the menu opened
float menu_time;rl::RLVector2 last_mouse;double mouse_moved_at;
int music_voice= -1;float music_gain;float music_target;
bool quit;float panel_anim;float fade_in;
float shot_orbit= -100;float shot_dist=3.2f;float shot_height=1.1f;   // --shot-orbit DEG [DIST HEIGHT]: inspection turntable around the menu mech (0 = front)

// ---------------------------------------------------------------- menu scene
fn void menu_enter()
{
    if(game_on)game_stop();vpt::controlled_rig= -1;paused=false;skills_open=false;cheat_open=false;third_person=false;tp_clear_fade();
    if(!generate_layer(MENU_SEED,0,true)) { io::printn("DEPTHS: could not build the menu scene");return; }
    menu_robot= -1;for(int r=0;r<vpt::rig_count;r++)if(is_player_rig(r))menu_robot=r;
    player=menu_robot;weapons_load();atmosphere_init();skills_reset();atmosphere_off=true;   // motes drift through the lens up close
    skill[SK_SCANNER]=1;skill[SK_ARMOR]=1;skill[SK_REGEN]=2;   // the menu bot shows a little gear (the run starts bare)
    if(menu_robot>=0)
    {
        vpt::Rig* r=&vpt::rigs[menu_robot];r.held=true;r.patrol=false;r.hunting=false;r.has_goal=false;
        menu_at={r.x,r.y,r.z};
        // The camera side with the deepest view past the bot (no hill right behind it) and a clear camera spot;
        // the bot is turned to face that camera.
        float best= -1;Vec d_best={0,0,1};Vec head=menu_at+(Vec){0,1.0f,0};
        for(int k=0;k<24;k++)
        {
            float a=(float)k*0.2618f;Vec d={math::cos(a),0,math::sin(a)};
            vpt::Pick cam_hit=vpt::pick_scene({head,d},-1,false);if(cam_hit.hit&&cam_hit.distance<5)continue;
            float open=0;
            for(int j= -2;j<=2;j++) { float b=a+3.14159f+(float)j*0.22f;vpt::Pick h=vpt::pick_scene({head+(Vec){0,0.4f,0},nrm((Vec){math::cos(b),0.06f,math::sin(b)})},-1,false);open+=h.hit?math::min(h.distance,60.0f):60; }
            float score=open/300+math::max(0.0f,sky_glow(a+3.14159f)-0.06f)*8;   // a deep view, and the galaxy band / moon in the frame
            if(dbg_menu)io::printfn("heading %d open %.0f glow %.3f score %.2f",k,open,sky_glow(a+3.14159f),score);
            if(score>best) { best=score;d_best=d; }
        }
        r.yaw=math::atan2(d_best[0],d_best[2]);r.desired_yaw=r.yaw;   // its face (local +z) toward the camera
        vpt::controlled_rig=menu_robot;vpt::control_input={};   // rigs only follow look_point when controlled (no input: it never walks)
        menu_f=d_best;menu_right={menu_f[2],0,-menu_f[0]};
    }
    profile_flush();refresh_slot_info();
    app_state=APP_MENU;panel=PANEL_MAIN;panel_anim=0;fade_in=0;
    if(music_voice<0||audio::voices[music_voice].state!=1||audio::voices[music_voice].sound!=SND_MENU_MUSIC)music_voice=audio::play_sound(SND_MENU_MUSIC,{},0.0f,1,false,true,0);
    music_gain=0;music_target=0.75f;
}
// Main menu mech choice: the diorama robot is swapped in place (same spot and heading), and the next run
// generates with it (player_robot). Saved in the settings file.
fn void menu_select_robot(int k)
{
    k=math::clamp(k,0,ROBOT_COUNT-1);player_robot=k;
    if(settings.robot!=k) { settings.robot=k;settings_save(); }
    if(menu_robot<0||menu_robot>=vpt::rig_count||robot_of(menu_robot)==k)return;
    char[256] saved;vpt::copy_text(&saved[0],256,(ZString)&vpt::message[0]);
    int def=vpt::load_rig(rl::text_format("assets/library/BLACK_START/%s.rig.json",ROBOT_RIGS[k]));
    vpt::copy_text(&vpt::message[0],256,(ZString)&saved[0]);if(def<0)return;
    vpt::rig_set_def(menu_robot,def);vpt::rigs[menu_robot].held=true;
    weapons_load();if(weapons_ready) { swap_stage=2;swap_t=0; }   // the new weapon swings up into place
    vpt::scene_revision++;   // the new parts + weapon join the atlas
    audio::play_sound(SND_WEAPON_LATCH,{},0.45f,k==1?0.8f:k==2?1.6f:1.2f,false,false,0);
}
// Three cards: name, designation, role. Click = swap the robot standing in the diorama.
fn void robot_picker(int x,int y,int w)
{
    ui::text("MECH",x,y,13,ui::MUTED);
    const ZString[ROBOT_COUNT] SHORT={"RATTLER","MORTAR","MAUL"};
    int cw=(w-16)/3;
    for(int k=0;k<ROBOT_COUNT;k++)if(segment(SHORT[k],x+k*(cw+8),y+20,cw,player_robot==k))menu_select_robot(k);
    int k=player_robot;ui::text(ROBOT_NAMES[k],x,y+64,15,ui::ACCENT);ui::text(ROBOT_ROLES[k],x,y+84,13,ui::MUTED);
}
fn void start_run()
{
    uint seed=0;for(int i=0;i<seed_len;i++)seed=seed*10+(uint)(seed_text[i]-'0');
    play_generated(seed,true,0);   // always --generate --detailed: a fresh layer 0 (random seed if empty)
    if(!game_on) { menu_enter();return; }
    atmosphere_off=false;app_state=APP_GAME;paused=false;third_person=false;tp_snap=true;cam_blend=1;vpt::orbit=0.68f;vpt::tilt=0.73f;vpt::zoom=5;
    music_target=0;
}
fn void schedule(int what,ZString label) { job=what;job_wait=2;job_text=label; }

// How much of the bright galaxy (band, moon) a view toward heading `a` frames: the sky PNG sampled with the
// tracer's own direction -> equirect mapping over the menu camera's field of view (CPU, once per menu).
fn float sky_glow(float a)
{
    static rl::RLImage sky;static bool tried;
    if(!tried) { tried=true;sky=rl::load_image("assets/skies/ash-waste-galaxy.png");if(sky.data)rl::image_resize(&sky,256,128); }
    if(!sky.data)return 0;
    float sum=0;int n=0;
    for(int i= -4;i<=4;i++)for(int j=1;j<=6;j++)
    {
        float yaw=a+(float)i*0.11f;float pitch=(float)j*0.09f;Vec d={math::cos(yaw)*math::cos(pitch),math::sin(pitch),math::sin(yaw)*math::cos(pitch)};
        float u=math::atan2(d[2],d[0])/6.2831853f+0.5f;float v=math::acos(vpt::clampf(d[1],-1,1))/3.14159265f;
        rl::RLColor c=rl::get_image_color(sky,vpt::clampi((int)(u*256),0,255),vpt::clampi((int)(v*128),0,127));
        sum+=((float)c[0]*0.3f+(float)c[1]*0.5f+(float)c[2]*0.2f)/255;n++;
    }
    return sum/(float)n;
}
// The menu camera: low, in front of the robot (it sits right of centre), tilted up toward the galaxy.
// A slow drift plus a little mouse parallax keeps the shot alive.
const float[ROBOT_COUNT] MENU_CAM_DIST={1,1.3f,0.9f};   // the wide Mortar needs the camera further back
fn rl::RLCamera3D menu_camera(rl::RLRectangle view)
{
    if(menu_robot<0||menu_robot>=vpt::rig_count)return vpt::camera();
    Vec at=menu_at;Vec f=menu_f;Vec right=menu_right;   // frozen at menu_enter (the camera must not chase the turning body)
    if(shot_orbit> -99)
    {
        float a=shot_orbit*0.017453293f;Vec p=at+(f*math::cos(a)+right*math::sin(a))*shot_dist+(Vec){0,shot_height,0};
        if(dbg_menu)io::printfn("orbit cam %.2f %.2f %.2f at %.2f %.2f %.2f",p[0],p[1],p[2],at[0],at[1],at[2]);
        return {.position=p,.target=at+(Vec){0,0.55f,0},.up={0,1,0},.fovy=40,.projection=rl::RLCameraProjection.PERSPECTIVE};
    }
    float far=MENU_CAM_DIST[robot_of(menu_robot)];
    rl::RLVector2 m=rl::get_mouse_position();float mx=vpt::clampf(m[0]/math::max(view.width,1.0f)-0.5f,-0.5f,0.5f);float my=vpt::clampf(m[1]/math::max(view.height,1.0f)-0.5f,-0.5f,0.5f);
    float t=menu_time;
    Vec drift={math::sin(t*0.11f)*0.18f,math::sin(t*0.07f+1)*0.07f,math::cos(t*0.09f)*0.12f};
    Vec pos=at+f*(3.9f*far)-right*(0.6f*far)+(Vec){0,0.8f,0}+drift+right*(mx*0.22f)+(Vec){0,-my*0.12f,0};
    Vec target=at-right*(1.45f*far)+(Vec){0,1.2f,0}+f*0.3f;   // aim left of the bot: it sits right of centre
    return {.position=pos,.target=target,.up={0,1,0},.fovy=52,.projection=rl::RLCameraProjection.PERSPECTIVE};
}
// The robot follows the mouse with its whole body (planted feet, no walking): the look point is where the mouse
// ray meets a plane between robot and camera, clamped inside the body's yaw limit so it never steps around.
fn void menu_robot_look(rl::RLCamera3D cam,rl::RLRectangle view)
{
    if(menu_robot<0||menu_robot>=vpt::rig_count)return;
    vpt::Rig* r=&vpt::rigs[menu_robot];
    rl::RLVector2 m=rl::get_mouse_position();if(m[0]!=last_mouse[0]||m[1]!=last_mouse[1]) { last_mouse=m;mouse_moved_at=rl::get_time(); }

    rl::RLRay ray=rl::get_screen_to_world_ray_ex(physical_point(m),cam,(int)(view.width*ui::scale),(int)(view.height*ui::scale));
    Vec head=menu_at+(Vec){0,0.6f,0};Vec f=menu_f;Vec right=menu_right;
    Vec p0=head+f*1.6f;float den=vpt::dot(ray.direction,f);if(math::abs(den)<0.0001f)return;
    float t=vpt::dot(p0-ray.position,f)/den;Vec hit=ray.position+ray.direction*t;
    Vec v=hit-head;float yaw=math::atan2(vpt::dot(v,right),vpt::dot(v,f));
    float flat=math::sqrt(vpt::dot(v,f)*vpt::dot(v,f)+vpt::dot(v,right)*vpt::dot(v,right));
    float pitch=math::atan2(v[1],math::max(flat,0.3f));
    if(rl::get_time()-mouse_moved_at>5) { float mt=menu_time;yaw=math::sin(mt*0.31f)*0.32f+math::sin(mt*0.83f)*0.06f;pitch=0.12f+math::sin(mt*0.23f+1)*0.14f; }   // idle: a slow look around
    if(shot_orbit> -99) { yaw=0;pitch=0.02f; }   // turntable shots: straight ahead
    yaw=vpt::clampf(yaw,-0.42f,0.42f);pitch=vpt::clampf(pitch,-0.35f,0.55f);   // inside the body's 30 deg aim: it never steps around
    r.has_look_point=true;r.look_point=head+(f*math::cos(yaw)+right*math::sin(yaw))*(4*math::cos(pitch))+(Vec){0,4*math::sin(pitch),0};
}
fn rl::RLVector2 physical_point(rl::RLVector2 m) => {m[0]*ui::scale,m[1]*ui::scale};

// ---------------------------------------------------------------- widgets (menu style)
fn bool big_button(ZString label,int x,int y,int w,int h=54)
{
    bool hover=ui::inside((float)x,(float)y,(float)w,(float)h);float k=hover?1:0;
    int dx=hover?8:0;
    rl::draw_rectangle_rounded({(float)(x+dx),(float)y,(float)w,(float)h},0.18f,6,hover?(rl::RLColor){60,52,36,235}:(rl::RLColor){24,24,26,200});
    rl::draw_rectangle(x+dx,y+10,hover?4:2,h-20,hover?ui::ACCENT:(rl::RLColor){120,108,90,255});
    ui::text(label,x+dx+26,y+h/2-11,22,hover?ui::ACCENT:ui::TEXT);
    (void)k;return hover&&rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT);
}
fn bool segment(ZString label,int x,int y,int w,bool on)
{
    bool hover=ui::inside((float)x,(float)y,(float)w,34);
    rl::draw_rectangle_rounded({(float)x,(float)y,(float)w,34},0.25f,6,on?(rl::RLColor){90,70,24,240}:hover?(rl::RLColor){60,56,54,230}:(rl::RLColor){34,33,32,220});
    if(on)rl::draw_rectangle_rounded_lines_ex({(float)x,(float)y,(float)w,34},0.25f,6,1.5f,ui::ACCENT);
    ui::text(label,x+(w-ui::text_width(label,15))/2,y+9,15,on?ui::ACCENT:hover?ui::TEXT:ui::MUTED);
    return hover&&rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT);
}
fn void settings_panel(int x,int y,int w)
{
    bool changed=false;
    ui::text("RENDER QUALITY",x,y,13,ui::MUTED);
    for(int q=0;q<3;q++)if(segment(QUALITY_NAMES[q],x+q*(w/3),y+20,w/3-8,settings.quality==q)) { settings.quality=q;changed=true; }
    y+=74;ui::text("LIGHT BOUNCES",x,y,13,ui::MUTED);
    for(int b=1;b<=3;b++)if(segment(rl::text_format("%d",b),x+(b-1)*(w/3),y+20,w/3-8,settings.bounces==b)) { settings.bounces=b;changed=true; }
    y+=74;ui::text("PIXELATED LIGHTING",x,y,13,ui::MUTED);
    if(segment("OFF",x,y+20,w/2-8,!settings.pixel_lights)) { settings.pixel_lights=false;changed=true; }
    if(segment("ON",x+w/2,y+20,w/2-8,settings.pixel_lights)) { settings.pixel_lights=true;changed=true; }
    y+=74;ui::text("DISPLAY",x,y,13,ui::MUTED);
    if(segment(settings.fullscreen?"FULLSCREEN":"WINDOWED",x,y+20,w/2-8,settings.fullscreen)) { settings.fullscreen=!settings.fullscreen;changed=true; }
    if(segment(settings.show_fps?"FPS SHOWN":"FPS HIDDEN",x+w/2,y+20,w/2-8,settings.show_fps)) { settings.show_fps=!settings.show_fps;changed=true; }
    y+=74;ui::text("VOLUME",x,y,13,ui::MUTED);
    {
        int bx=x;int by=y+30;int bw=w-8;bool hover=ui::inside((float)bx-6,(float)by-12,(float)bw+12,26);
        if(hover&&rl::is_mouse_button_down(rl::RLMouseButton.LEFT)) { float v=vpt::clampf(((float)rl::get_mouse_x()-(float)bx)/(float)bw,0,1);if(v!=settings.volume) { settings.volume=v;changed=true; } }
        rl::draw_rectangle_rounded({(float)bx,(float)by-3,(float)bw,6},0.5f,4,{60,56,54,255});
        rl::draw_rectangle_rounded({(float)bx,(float)by-3,(float)bw*settings.volume,6},0.5f,4,ui::ACCENT);
        rl::draw_circle(bx+(int)((float)bw*settings.volume),by,hover?9:7,ui::ACCENT);
        ZString pct=rl::text_format("%d%%",(int)(settings.volume*100+0.5f));ui::text(pct,x+w-8-ui::text_width(pct,13),y,13,ui::ACCENT);
    }
    if(changed)settings_save();
}
// Digits only, optional; Enter launches, Backspace edits.
fn void seed_field(int x,int y,int w)
{
    ui::text("SEED  (optional)",x,y,13,ui::MUTED);
    int by=y+20;bool hover=ui::inside((float)x,(float)by,(float)w,46);
    if(rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))seed_focus=hover;
    rl::draw_rectangle_rounded({(float)x,(float)by,(float)w,46},0.18f,6,{20,20,22,230});
    rl::draw_rectangle_rounded_lines_ex({(float)x,(float)by,(float)w,46},0.18f,6,1.5f,seed_focus?ui::ACCENT:(rl::RLColor){80,73,69,255});
    if(seed_focus)
    {
        int c=rl::get_char_pressed();
        while(c>0) { if(c>='0'&&c<='9'&&seed_len<9) { seed_text[seed_len++]=(char)c;seed_text[seed_len]=0; }c=rl::get_char_pressed(); }
        if((rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE)||rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))&&seed_len>0) { seed_len--;seed_text[seed_len]=0; }
    }
    seed_text[seed_len]=0;
    if(seed_len) { ui::text((ZString)&seed_text[0],x+16,by+12,22,ui::TEXT); } else { ui::text("random",x+24,by+12,22,{110,102,96,255}); }
    if(seed_focus&&math::sin(rl::get_time()*6)>0) { int cx=x+16+(seed_len?ui::text_width((ZString)&seed_text[0],22):0)+2;rl::draw_rectangle(cx,by+11,2,24,ui::ACCENT); }
}
fn void draw_menu(rl::RLRectangle view)
{
    float dt=math::min(rl::get_frame_time(),0.05f);panel_anim=math::min(1.0f,panel_anim+dt*4);fade_in=math::min(1.0f,fade_in+dt*0.8f);
    if(panel==PANEL_BESTIARY) { if(draw_bestiary(view)) { panel=PANEL_MAIN;panel_anim=0; }return; }
    // left shade for the text column + a soft top/bottom vignette
    rl::draw_rectangle_gradient_h(0,0,(int)(view.width*0.55f),(int)view.height,{8,8,10,215},{8,8,10,0});
    rl::draw_rectangle_gradient_v(0,(int)(view.height*0.78f),(int)view.width,(int)(view.height*0.22f)+1,{0,0,0,0},{0,0,0,150});
    int x=(int)(view.width*0.075f);int y=(int)(view.height*0.2f);
    float a=fade_in;rl::RLColor tc=ui::TEXT;tc[3]=(char)(int)(255*a);rl::RLColor mc=ui::MUTED;mc[3]=(char)(int)(255*a);rl::RLColor ac=ui::ACCENT;ac[3]=(char)(int)(255*a);
    ui::text("DEPTHS",x,y,82,tc);
    rl::draw_rectangle(x+3,y+96,(int)(180*a),2,ac);
    ui::text("a mech expedition below the ash",x+3,y+110,17,mc);
    int by=y+190;int w=320;int slide=(int)((1-panel_anim)*(1-panel_anim)*40);
    if(panel==PANEL_MAIN)
    {
        robot_picker(x-slide,by,w);by+=124;
        if(big_button("START GAME",x-slide,by,w)) { panel=PANEL_START;panel_anim=0;seed_focus=true;audio::play_sound(SND_WEAPON_LATCH,{},0.4f,1.5f,false,false,0); }
        if(big_button("BESTIARY",x-slide,by+66,w)) { panel=PANEL_BESTIARY;panel_anim=0;erase_armed=false;audio::play_sound(SND_WEAPON_LATCH,{},0.4f,1.5f,false,false,0); }
        if(save_slot>=0) { ZString bs=rl::text_format("%d/%d",discovered_count(&profile),SPECIES_COUNT);ui::text(bs,x-slide+w-22-ui::text_width(bs,14),by+66+19,14,ui::MUTED); }
        if(big_button("SETTINGS",x-slide,by+132,w)) { panel=PANEL_SETTINGS;panel_anim=0;audio::play_sound(SND_WEAPON_LATCH,{},0.4f,1.5f,false,false,0); }
        if(big_button("QUIT",x-slide,by+198,w))quit=true;
        if(save_slot>=0)ui::text(rl::text_format("save slot %d  /  %s",save_slot+1,slot_summary(save_slot)),x-slide,by+266,12,mc);
        if(rl::is_key_pressed(rl::RLKeyboardKey.ENTER)) { panel=PANEL_START;panel_anim=0;seed_focus=true; }
    }
    else if(panel==PANEL_START)
    {
        if(save_slot>=0) { slot_picker(x-slide,by,w);by+=86; }
        seed_field(x-slide,by,w);
        if(big_button("LAUNCH",x-slide,by+90,w)||rl::is_key_pressed(rl::RLKeyboardKey.ENTER)||rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER)) { audio::play_sound(SND_WEAPON_WHIR,{},0.6f,0.8f,false,false,0);schedule(JOB_RUN,"DESCENDING TO THE ASH WASTE"); }
        if(big_button("BACK",x-slide,by+156,w)||rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE)) { panel=PANEL_MAIN;panel_anim=0; }
        ui::text("WASD move    mouse aim / fire    V camera    T skills    E use    SHIFT dash",x,by+232,13,mc);
    }
    else
    {
        settings_panel(x-slide,by-20,w+60);
        if(big_button("BACK",x-slide,by+370,w)||rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE)) { panel=PANEL_MAIN;panel_anim=0; }
    }
    ui::text("v0.1",(int)view.width-50,(int)view.height-26,12,{120,112,104,(char)(int)(200*a)});
}
// ---------------------------------------------------------------- in-game pause
fn void draw_pause(rl::RLRectangle view)
{
    rl::draw_rectangle_rec(view,{6,6,8,170});
    int w=320;int x=(int)(view.width/2)-w/2;int y=(int)(view.height*0.3f);
    if(pause_panel==PANEL_SETTINGS)
    {
        ui::text("SETTINGS",x,y-60,30,ui::TEXT);settings_panel(x,y,w+60);
        if(big_button("BACK",x,y+390,w)) { pause_panel=PANEL_MAIN; }
        return;
    }
    ui::text("PAUSED",x,y-60,30,ui::TEXT);
    if(big_button("RESUME",x,y,w))paused=false;
    if(big_button("SETTINGS",x,y+66,w))pause_panel=PANEL_SETTINGS;
    if(big_button("MAIN MENU",x,y+132,w)) { paused=false;schedule(JOB_MENU,"BACK TO THE SURFACE"); }
    if(big_button("QUIT",x,y+198,w))quit=true;
}
fn void draw_loading(rl::RLRectangle view)
{
    rl::draw_rectangle_rec(view,{6,6,8,235});
    int w=ui::text_width(job_text,22);ui::text(job_text,(int)(view.width/2)-w/2,(int)(view.height/2)-12,22,ui::TEXT);
    rl::draw_rectangle((int)(view.width/2)-60,(int)(view.height/2)+24,120,2,ui::ACCENT);
}

// ---------------------------------------------------------------- main
fn void main(String[] args)
{
    bool packed=vpt::pack_init();   // single-file release: assets served from the binary itself (vfs.c3)
    if(!packed&&!rl::directory_exists("assets")) { ZString app=rl::get_application_directory();if(app&&rl::directory_exists(rl::text_format("%sassets",app)))(void)rl::change_directory(app); }
    settings_load();player_robot=settings.robot;
    ZString shot=null;int shot_panel=PANEL_MAIN;int slot_arg= -1;   // --shot PATH [--panel start|settings]: headless menu screenshot (offscreen)
    for(int i=1;i<(int)args.len;i++)
    {
        if(args[i]=="--shot"&&i+1<(int)args.len)shot=(ZString)args[++i].ptr;
        if(args[i]=="--run-test")run_test=true;   // headless: menu -> run (seed 77) -> F2 layer -1 -> menu, prints DEPTHS RUN TEST
        if(args[i]=="--bestiary-entry"&&i+1<(int)args.len)bst_sel=math::clamp(args[++i].to_int()??0,0,SPECIES_COUNT-1);   // shots
        if(args[i]=="--slot"&&i+1<(int)args.len)slot_arg=math::clamp(args[++i].to_int()??1,1,SAVE_SLOTS)-1;   // shots: show this save slot (normally off in --shot / --run-test)
        if(args[i]=="--robot"&&i+1<(int)args.len)player_robot=math::clamp(args[++i].to_int()??0,0,ROBOT_COUNT-1);   // shots / tests: which mech (not saved)
        if(args[i]=="--debug-menu")dbg_menu=true;
        if(args[i]=="--shot-orbit"&&i+1<(int)args.len)
        {
            shot_orbit=(float)(args[++i].to_double()??0);
            if(i+2<(int)args.len&&args[i+1][0]!='-') { shot_dist=(float)(args[++i].to_double()??3.2);shot_height=(float)(args[++i].to_double()??1.1); }
        }
        if(args[i]=="--panel"&&i+1<(int)args.len) { String p=args[++i];shot_panel=p=="start"?PANEL_START:p=="settings"?PANEL_SETTINGS:p=="bestiary"?PANEL_BESTIARY:PANEL_MAIN; }
    }
    rl::set_trace_log_level(rl::RLTraceLogLevel.WARNING);rl::set_config_flags(rl::RLConfigFlag.WINDOW_RESIZABLE|rl::RLConfigFlag.VSYNC_HINT);
    rl::init_window(1600,900,"DEPTHS");defer rl::close_window();
    if(shot) { rl::set_window_min_size(1600,900);rl::set_window_max_size(1600,900); }   // fixed size: tiling WMs float it, shots stay 16:9
    rl::set_window_min_size(960,600);rl::set_exit_key((rl::RLKeyboardKey)0);
    vpt::new_scene(64);vpt::scene_open=false;vpt::config_enabled=false;vpt::show_grid=false;
    defer vpt::release_assets();defer vpt::release_scene();defer vpt::release_renderer();
    vpt::init_renderer();depths_world_init();
    audio::allowed=shot==null&&!run_test;audio_init();defer audio_close();int frames=0;rl::RLRenderTexture2D shot_rt;if(shot)shot_rt=rl::load_render_texture(1600,900);
    ui::load_ui_font();ui::map_layout();
    // Profiles: the active slot is saved as you play. Screenshot / test runs never write saves unless --slot is given.
    if(slot_arg>=0||(!shot&&!run_test))profile_select(slot_arg>=0?slot_arg:settings.slot);
    defer { profile_flush();bestiary_release(); }
    schedule(JOB_MENU,"WAKING THE MH-6");
    while(!rl::window_should_close()&&!quit)
    {
        @pool()
        {
            float frame_dt=math::min(rl::get_frame_time(),0.05f);
            if(vpt::ui_scale<=0)vpt::ui_scale=1;
            ui::scale=vpt::clampf(math::round((float)rl::get_screen_height()/1000*4)/4,1,2.5f);rl::set_mouse_scale(1/ui::scale,1/ui::scale);vpt::render_scale=1/ui::scale;
            rl::RLRectangle view={0,0,(float)ui::sw(),(float)ui::sh()};
            if(shot) { ui::scale=1;rl::set_mouse_scale(1,1);vpt::render_scale=1;view={0,0,1600,900}; }   // shots trace a fixed 16:9 frame whatever the window is
            // long jobs: show the loading screen for a frame, then do the work
            if(job!=JOB_NONE&&job_wait<=0)
            {
                int what=job;job=JOB_NONE;
                if(what==JOB_MENU) { menu_enter(); } else { start_run(); }
                continue;
            }
            settings_apply();
            if(run_test&&run_test_step())break;
            music_gain+=(music_target-music_gain)*math::min(1.0f,frame_dt*(music_target>music_gain?0.6f:2.5f));audio::set_voice_gain(music_voice,music_gain);
            if(music_target==0&&music_gain<0.01f&&music_voice>=0&&audio::voices[music_voice].state==1&&audio::voices[music_voice].sound==SND_MENU_MUSIC) { audio::voices[music_voice].state=0;music_voice= -1; }
            rl::RLCamera3D cam;
            if(app_state==APP_MENU)
            {
                menu_time+=frame_dt;game_time+=frame_dt;
                cam=menu_camera(view);menu_robot_look(cam,view);
                vpt::update_rigs(frame_dt);
                vpt::dyn_begin();vpt::game_light_count=0;weapon_update(frame_dt);weapons_draw();menu_lights();skills_update(frame_dt);skills_draw_robot();atmosphere_draw(frame_dt);vpt::dyn_end();
                set_roof_visible(false);
            }
            else
            {
                if(!game_on) { schedule(JOB_MENU,"BACK TO THE SURFACE");job_wait=0;continue; }
                // input
                bool menu_layer=paused||skills_open;
                if(rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
                {
                    if(skills_open) { toggle_skills(); }
                    else if(cheat_open) { cheat_open=false; }
                    else if(game_over) { schedule(JOB_MENU,"BACK TO THE SURFACE"); }
                    else { paused=!paused;pause_panel=PANEL_MAIN; }
                }
                vpt::control_input={};
                if(!paused)
                {
                    if(ui::key('r'))game_restart();
                    if(ui::key('v'))toggle_third_person();
                    if(!skills_open&&ui::key('e')) { if(crate_in_reach()>=0) { crate_interact(); } else { shop_interact(); } }
                    if(ui::key('t'))toggle_skills();
                    if(!skills_open&&(rl::is_key_pressed(rl::RLKeyboardKey.LEFT_SHIFT)||rl::is_key_pressed(rl::RLKeyboardKey.RIGHT_SHIFT)))dash_request=true;
                    if(rl::is_key_pressed(rl::RLKeyboardKey.F2))cheat_open=!cheat_open;
                    if(!skills_open&&rl::is_key_pressed(rl::RLKeyboardKey.F3))weapon_toggle_mount();
                    if(!skills_open&&!tp_active())
                    {
                        rl::RLVector3 right={math::cos(vpt::orbit),0,-math::sin(vpt::orbit)};rl::RLVector3 forward={-math::sin(vpt::orbit),0,-math::cos(vpt::orbit)};
                        float a=(rl::is_key_down(rl::RLKeyboardKey.D)?1.0f:0)-(rl::is_key_down(rl::RLKeyboardKey.A)?1.0f:0);float b=(rl::is_key_down(rl::RLKeyboardKey.W)?1.0f:0)-(rl::is_key_down(rl::RLKeyboardKey.S)?1.0f:0);
                        vpt::control_input=right*a+forward*b;
                        rl::RLVector2 delta=rl::get_mouse_delta();
                        if(rl::is_mouse_button_down(rl::RLMouseButton.RIGHT)) { vpt::orbit-=delta[0]*0.005f;vpt::tilt=vpt::clampf(vpt::tilt+delta[1]*0.004f,0.3f,1.4f); }
                        vpt::zoom=vpt::clampf(vpt::zoom*math::pow(0.9f,rl::get_mouse_wheel_move()),3,14);
                    }
                }
                float game_dt=menu_layer?0:frame_dt;
                tp_update_capture(game_on&&third_person&&!paused&&!cheat_open&&!skills_open&&rl::is_window_focused());
                cam=vpt::camera();
                rl::RLVector2 mouse=rl::get_mouse_position();
                rl::RLRay mouse_ray=rl::get_screen_to_world_ray_ex(physical_point(mouse),cam,(int)(view.width*ui::scale),(int)(view.height*ui::scale));
                bool tp=tp_active()&&!tp_snap;if(tp&&!paused) { tp_input(game_dt);mouse_ray=tp_aim_ray(); }
                bool over_cheats=cheat_open&&ui::inside(cheat_rect.x,cheat_rect.y,cheat_rect.width,cheat_rect.height);
                game_update(game_dt,mouse_ray,true,!menu_layer&&!over_cheats&&rl::is_mouse_button_down(rl::RLMouseButton.LEFT));
                apply_layer_transition();
                vpt::update_rigs(menu_layer?0:rl::get_frame_time());
                game_post(game_dt);
                if(game_on&&player>=0&&player<vpt::rig_count)
                {
                    vpt::Rig r=vpt::rigs[player];vpt::focus={r.x,r.y+0.4f,r.z};vpt::focus+=shake_offset();
                    cam=swoosh(tp_active()?tp_camera(r,game_dt):vpt::camera(),rl::get_frame_time());
                    audio_update({r.x,r.y+1,r.z},cam);
                }
                set_roof_visible(tp_active()&&(cam_blend>=0.8f||!game_on));
            }
            if(shot&&app_state==APP_MENU) { panel=shot_panel;mouse_moved_at= -100; }   // idle look-around
            if(app_state==APP_MENU&&panel==PANEL_BESTIARY)bestiary_prepare();   // offscreen portrait, before the frame starts
            rl::begin_drawing();rl::clear_background({8,8,10,255});
            vpt::draw_scene(cam,ui::physical(view));ui::ui_transform();
            if(app_state==APP_MENU) { draw_menu(view); }
            else
            {
                draw_game_hud(view,cam);
                if(paused)draw_pause(view);
            }
            if(settings.show_fps)ui::text(rl::text_format("%d FPS",rl::get_fps()),(int)view.width-80,8,13,ui::ACCENT);
            if(job!=JOB_NONE) { draw_loading(view);job_wait--; }
            rl::end_mode2d();rl::end_drawing();
            if(dbg_menu&&app_state==APP_MENU&&menu_robot>=0&&frames%30==0) { vpt::Rig* rr=&vpt::rigs[menu_robot];Vec fz=vpt::rig_dir(rr,{0,0,-1});Vec pz=vpt::rig_dir(rr,{0,0,1});io::printfn("f%d yaw %.2f -z.f %.2f +z.f %.2f pos %.2f %.2f",frames,rr.yaw,vpt::dot(fz,menu_f),vpt::dot(pz,menu_f),rr.x,rr.z); }
            if(shot&&app_state==APP_MENU&&job==JOB_NONE&&++frames==150)
            {
                shot_scene(rl::text_format("%s.scene.png",shot));
                rl::begin_texture_mode(shot_rt);rl::clear_background({0,0,0,0});rl::begin_mode2d({{0,0},{0,0},0,1});draw_menu({0,0,1600,900});rl::end_mode2d();rl::end_texture_mode();
                rl::RLImage img=rl::load_image_from_texture(shot_rt.texture);rl::image_flip_vertical(&img);(void)rl::export_image(img,rl::text_format("%s.ui.png",shot));rl::unload_image(img);break;
            }
        };
    }
}
// --shot: the traced frame, tone mapped like the display pass (ACES + gamma), saved as PNG.
fn void shot_scene(ZString path)
{
    rl::RLTexture texture=vpt::output_texture();rl::RLVector4* pixels=vpt::read_pixels(texture);defer rl::mem_free(pixels);
    rl::RLColor* colors=(rl::RLColor*)rl::mem_alloc((uint)(texture.width*texture.height*4));defer rl::mem_free(colors);
    for(int y=0;y<texture.height;y++)for(int x=0;x<texture.width;x++)
    {
        int from=y*texture.width+x;int to=(texture.height-1-y)*texture.width+x;
        for(int c=0;c<3;c++) { float v=pixels[from][c]*vpt::lighting.exposure;v=vpt::clampf((v*(2.51f*v+0.03f))/(v*(2.43f*v+0.59f)+0.14f),0,1);colors[to][c]=(char)(math::pow(v,1.0f/2.2f)*255+0.5f); }
        colors[to][3]=255;
    }
    (void)rl::export_image({colors,texture.width,texture.height,1,rl::RLPixelFormat.UNCOMPRESSED_R8G8B8A8},path);
}
// A warm key light from the front-left and a cool rim from behind: the bot reads against the night sky.
fn void menu_lights()
{
    if(menu_robot<0||menu_robot>=vpt::rig_count)return;Vec at=menu_at;Vec f=menu_f;Vec right=menu_right;
    vpt::game_light(at+f*2.2f-right*1.6f+(Vec){0,1.9f,0},{26,17,9},7);
    vpt::game_light(at-f*1.8f+right*1.2f+(Vec){0,1.4f,0},{6,9,16},5);
}
// --run-test: drive the real app loop through a run and back (asserts, then quits).
fn bool run_test_step()
{
    test_frames++;
    switch(test_step)
    {
        case 0: if(app_state==APP_MENU&&job==JOB_NONE&&test_frames>20) { seed_len=2;seed_text[0]='7';seed_text[1]='7';seed_text[2]=0;schedule(JOB_RUN,"TEST");test_step=1;test_frames=0; }
        case 1:
            if(app_state==APP_GAME&&test_frames>90)
            {
                assert(game_on&&gen_layer==0&&gen_seed==77,"Start game must generate a detailed layer 0 from the seed.");
                assert(vpt::lighting.light_pixel==0,"Pixelated lighting is off by default.");
                assert(robot_of(player)==player_robot&&weapon==ROBOT_WEAPON[player_robot],"The run uses the mech chosen in the menu, with its weapon.");
                skill_points=3;cheat_layer= -1;test_step=2;test_frames=0;
            }
        case 2:
            if(test_frames>60)
            {
                assert(game_on&&gen_layer== -1&&skill_points==3,"F2 layer jump keeps the run (skill points).");
                assert(robot_of(player)==player_robot,"The next layer spawns the same mech.");
                paused=true;schedule(JOB_MENU,"TEST");test_step=3;test_frames=0;
            }
        case 3:
            if(app_state==APP_MENU&&job==JOB_NONE&&test_frames>30)
            {
                assert(!game_on&&gen_layer==0&&vpt::controlled_rig==menu_robot,"Main menu returns to the diorama.");
                io::printn("DEPTHS RUN TEST PASSED: menu -> run (seed 77, layer 0) -> F2 layer -1 (skills kept) -> menu");return true;
            }
        default:
    }
    return false;
}
