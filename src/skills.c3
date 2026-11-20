module depths;
import std::math;
import raylib6::rl;
import vpt;

// Skill tree (per run). Kills give XP, every level a skill point; T opens the tree (paused). Crates and drops
// install one free level in a random node that is unlockable right now; the shop console (L-1) is a station:
// +1 point once, and one full respec. Some skills change the robot (armor plates, scanner dish, targeting
// optic + laser, coolant cells, dash thrusters, 2-3 guns). Replaces the old flat modifiers.

const int SK_SERVO=0;const int SK_DASH=1;const int SK_OVERCLOCK=2;const int SK_MULTI=3;const int SK_PIERCE=4;const int SK_RICOCHET=5;
const int SK_REGEN=6;const int SK_ARMOR=7;const int SK_NANITES=8;const int SK_SCANNER=9;const int SK_AIMBOT=10;const int SK_COUNT=11;
const int BRANCHES=4;
const ZString[BRANCHES] BRANCH_NAMES={"MOBILITY","FIREPOWER","HULL","SYSTEMS"};
const rl::RLColor[BRANCHES] BRANCH_COLOR={{142,192,124,255},{254,128,25,255},{184,187,38,255},{211,134,155,255}};
const uint[BRANCHES] BRANCH_BGR={0x7cc08e,0x1980fe,0x26bbb8,0x9b86d3};   // the same colours as 0xBBGGRR (dyn tints, popups)
struct SkillDef { ZString name;ZString icon;int branch;int max;int req;int req_level;float col;int row;ZString[3] level_text;ZString desc; }
const SkillDef[SK_COUNT] SKILLS={
    {"Servo boost","servo",0,3,-1,0,0,0,{"+15% move speed","+30% move speed","+45% move speed"},"Overdriven leg servos. The whole gait speeds up, turning and strafing included."},
    {"Dash thrusters","dash",0,1,SK_SERVO,2,0,1,{"SHIFT: dash ~3 m, 2.2 s cooldown, no damage during the burst","",""},"Twin cold-gas nozzles under the tail. Burst out of a bite or across a gap."},
    {"Overclock","overclock",1,3,-1,0,1.5f,0,{"fire rate x1.2","fire rate x1.45","fire rate x1.75"},"Actuators and feed run hot. Every weapon cycles faster, the rocket windup too."},
    {"Multi-gun","multigun",1,2,SK_OVERCLOCK,1,1.5f,1,{"2 guns: every shot x2","3 guns: every shot x3",""},"Extra weapons on a wider yoke. All guns fire together from their own muzzles."},
    {"Piercing rounds","pierce",1,2,SK_MULTI,1,1,2,{"bolts pass through 1 creature","bolts pass through 3 creatures",""},"Hardened penetrators that keep going after the first body."},
    {"Ricochet","ricochet",1,1,SK_MULTI,1,2,2,{"bolts bounce off rock once","",""},"Glancing shots skip off walls and find targets around corners."},
    {"Regen","regen",2,3,-1,0,3,0,{"+1.5 hull/s after 3 s unhurt","+3 hull/s after 3 s unhurt","+5 hull/s after 3 s unhurt"},"Coolant cells patch the hull whenever nothing is biting you."},
    {"Armor plating","armor",2,3,SK_REGEN,1,3,1,{"-15% damage taken","-28% damage taken","-40% damage taken"},"Bolted plates between the hips, then a glacis and pauldrons, then heavy skirts."},
    {"Repair nanites","nanites",2,2,SK_ARMOR,1,3,2,{"every kill repairs 3 hull","every kill repairs 6 hull",""},"A swarm feeds on what you kill and patches the hull."},
    {"Scanner","scanner",3,1,-1,0,4,0,{"outlines creatures through walls","",""},"A spinning dish on the rear deck. Nothing sneaks up on you any more."},
    {"Targeting AI","aimbot",3,1,SK_SCANNER,1,4,1,{"auto-aim: locks the nearest visible creature","",""},"An optic on the shoulder with a laser designator. Your shots find their mark."},
};
int[SK_COUNT] skill;int skill_points;int xp;int level=1;bool skills_open;bool skills_station;bool station_point_taken;bool station_respec_used;
int sk_hover= -1;float[SK_COUNT] sk_pop;float skills_time;float level_glow;
rl::RLTexture2D[SK_COUNT] sk_icon;rl::RLTexture2D icon_point;rl::RLTexture2D icon_lock;rl::RLTexture2D icon_crate;bool icons_tried;
float dash_cool;float dash_t;bool dash_request;Vec dash_dir;float since_hurt=99;
Vec aim_lock_p;float aim_lock_t;float dish_angle;int flame_asset= -1;int laser_dot_asset= -1;
struct UiSpark { rl::RLVector2 p;rl::RLVector2 v;float t;rl::RLColor c; }
UiSpark[48] sparks;int spark_next;

// ---------------------------------------------------------------- numbers
fn int xp_to_next(int lv) => 25+15*(lv-1);
fn float skill_move_mul() => 1+0.15f*(float)skill[SK_SERVO];
fn float skill_rate_mul() { const float[4] R={1,1.2f,1.45f,1.75f};return R[math::clamp(skill[SK_OVERCLOCK],0,3)]; }
fn int skill_pierce() { const int[3] P={0,1,3};return P[math::clamp(skill[SK_PIERCE],0,2)]; }
fn int skill_bounces() => skill[SK_RICOCHET];
fn float skill_regen() { const float[4] R={0,1.5f,3,5};return R[math::clamp(skill[SK_REGEN],0,3)]; }
fn float skill_armor_mul() { const float[4] A={1,0.85f,0.72f,0.6f};return A[math::clamp(skill[SK_ARMOR],0,3)]; }
fn float skill_kill_heal() => 3*(float)skill[SK_NANITES];
fn bool skill_scanner() => skill[SK_SCANNER]>0;
fn bool aim_assist() => auto_aim||skill[SK_AIMBOT]>0;
fn bool skills_menu_open() => skills_open;
fn int xp_for_kill(int r)
{
    if(is_layer_boss(r))return 80;
    switch(kind[r])
    {
        case SKITTER: return 3;
        case FLUTTER: return 5;
        case SCAVENGER: return 6;
        case BLOATER: return 6;
        case NEST: return vpt::rigs[r].scale>1.2f?18:12;
        case CRAWLER: return vpt::rigs[r].scale>1.2f?30:18;
        case STALKER: return 16;
        default: return 0;
    }
}

// Carried through the rift (stations are per layer, so their flags are not).
struct SkillState { int[SK_COUNT] skill;int points;int xp;int level; }
fn SkillState skills_save() => {skill,skill_points,xp,level};
fn void skills_load(SkillState s) { skill=s.skill;skill_points=s.points;xp=s.xp;level=s.level; }
// ---------------------------------------------------------------- state changes
fn void skills_reset()
{
    skill={};skill_points=0;xp=0;level=1;skills_open=false;skills_station=false;station_point_taken=false;station_respec_used=false;
    sk_pop={};level_glow=0;dash_cool=0;dash_t=0;dash_request=false;since_hurt=99;aim_lock_t=0;sparks={};
    if(flame_asset<0) { flame_asset=vpt::make_cube_asset("thrust-flame",1,vpt::rgba(140,210,255),3.0f);if(flame_asset>=0)vpt::pinned_assets[flame_asset]=true; }
    if(laser_dot_asset<0) { laser_dot_asset=vpt::make_cube_asset("laser-dot",1,vpt::rgba(255,40,30),4.0f);if(laser_dot_asset>=0)vpt::pinned_assets[laser_dot_asset]=true; }
}
fn bool skill_unlocked(int s) => SKILLS[s].req<0||skill[SKILLS[s].req]>=SKILLS[s].req_level;
fn bool skill_available(int s) => skill[s]<SKILLS[s].max&&skill_unlocked(s);
fn void gain_xp(int amount)
{
    if(amount<=0)return;xp+=amount;
    while(xp>=xp_to_next(level))
    {
        xp-=xp_to_next(level);level++;skill_points++;level_glow=1;
        popup_title=rl::text_format("LEVEL %d",level);popup_info="+1 skill point   -   T opens the skill tree";popup_color=0x2fbdfa;popup_t=POPUP_TIME;
        audio::play_sound(SND_PICKUP,{},1.0f,1.32f,false,false,0);audio::play_sound(SND_WEAPON_LATCH,{},0.5f,1.9f,false,false,0);
        if(player>=0&&player<vpt::rig_count)
        {
            vpt::Rig* me=&vpt::rigs[player];Vec at={me.x,me.y+0.5f,me.z};flash(at+(Vec){0,1,0},{120,90,25},7,0.5f);
            for(int k=0;k<26;k++) { float a=(float)k*0.2417f*6.2832f;spawn_debris(at,(Vec){math::cos(a)*3,4+gr()*3,math::sin(a)*3},0.03f,0x2fbdfa,2.5f,0.9f); }
        }
    }
}
// Effects the moment a level lands (visual/weapon changes need a nudge).
fn void skill_applied(int s)
{
    if(s==SK_MULTI&&weapons_ready&&swap_stage==0) { swap_stage=2;swap_t=0;audio::play_sound(SND_WEAPON_WHIR+take(&last_whir_take),muzzle(0),0.7f,0.9f,true,false,0); }   // the new gun swings up
}
fn bool skill_install(int s,bool free)
{
    if(s<0||s>=SK_COUNT||!skill_available(s)||(!free&&skill_points<=0))return false;
    if(!free)skill_points--;skill[s]++;sk_pop[s]=1;skill_applied(s);
    audio::play_sound(SND_WEAPON_LATCH+take(&last_latch_take),{},0.8f,1.05f,false,false,0);audio::play_sound(SND_PICKUP,{},0.7f,1.0f+0.08f*(float)skill[s],false,false,0);
    return true;
}
fn int random_available_skill()
{
    int[SK_COUNT] free;int n=0;for(int s=0;s<SK_COUNT;s++)if(skill_available(s))free[n++]=s;
    return n?free[math::min(n-1,(int)(gr()*(float)n))]:-1;
}
// Crate / drop: one free level in a node unlockable right now (hull repair once the tree is full).
fn void grant_random_perk(Vec at)
{
    int s=random_available_skill();flash(at+(Vec){0,0.8f,0},{120,90,25},8,0.5f);
    if(s<0) { player_hp=math::min(100.0f,player_hp+30);popup_title="HULL REPAIRED";popup_info="+30 hull (every skill is maxed)";popup_color=0x4fb8b8;popup_t=POPUP_TIME;return; }
    skill_install(s,true);
    popup_title=rl::text_format("PERK  -  %s",SKILLS[s].name);popup_info=SKILLS[s].level_text[skill[s]-1];popup_color=BRANCH_BGR[SKILLS[s].branch];popup_t=POPUP_TIME;
    vpt::report(rl::text_format("Free perk: %s level %d (%s).",SKILLS[s].name,skill[s],SKILLS[s].level_text[skill[s]-1]));
}
fn void skills_respec()
{
    int refund=0;for(int s=0;s<SK_COUNT;s++) { refund+=skill[s];skill[s]=0; }
    skill_points+=refund;station_respec_used=true;
    if(weapons_ready&&swap_stage==0) { swap_stage=2;swap_t=0; }
    audio::play_sound(SND_WEAPON_WHIR,{},0.7f,0.8f,false,false,0);
    popup_title="SKILLS RESET";popup_info=rl::text_format("%d points back - spend them again",refund);popup_color=0x9b86d3;popup_t=POPUP_TIME;
}
// The shop console as a skill station: +1 point the first time, one respec.
fn void open_skill_station()
{
    skills_open=true;skills_station=true;sk_hover= -1;
    if(!station_point_taken) { station_point_taken=true;skill_points++;level_glow=1;audio::play_sound(SND_PICKUP,{},1.0f,1.2f,false,false,0); }
}
fn void toggle_skills()
{
    if(!game_on||game_over)return;
    skills_open=!skills_open;skills_station=false;sk_hover= -1;
    audio::play_sound(SND_WEAPON_LATCH,{},0.35f,skills_open?1.6f:1.3f,false,false,0);
}
fn bool station_live() => !station_point_taken||!station_respec_used;

// ---------------------------------------------------------------- per frame (game time)
fn void skills_update(float dt)
{
    skills_time+=dt;level_glow=math::max(0.0f,level_glow-dt*0.6f);dish_angle+=dt*2.6f;
    for(int s=0;s<SK_COUNT;s++)sk_pop[s]=math::max(0.0f,sk_pop[s]-dt*2.5f);
    aim_lock_t=math::max(0.0f,aim_lock_t-dt);dash_cool=math::max(0.0f,dash_cool-dt);
    since_hurt+=dt;
    if(skill_regen()>0&&since_hurt>3&&player_hp<100&&!game_over)player_hp=math::min(100.0f,player_hp+skill_regen()*dt);
    if(player<0||player>=vpt::rig_count)return;
    vpt::Rig* me=&vpt::rigs[player];
    if(dash_t>0)
    {
        dash_t-=dt;me.knock=dash_dir*17;   // a short powered burst (collision still applies)
        if(gr()<0.6f)spawn_debris({me.x,me.y+0.05f,me.z},(Vec){(gr()-0.5f)*2,1+gr(),(gr()-0.5f)*2}-dash_dir*2,0.04f,0x646e78,0,0.5f);
    }
    if(dash_request)
    {
        dash_request=false;
        if(skill[SK_DASH]>0&&dash_cool<=0&&!game_over)
        {
            Vec d=vpt::control_input;d[1]=0;if(vpt::dot(d,d)<0.01f)d=vpt::rig_dir(me,{0,0,1});d[1]=0;dash_dir=nrm(d);
            dash_t=0.17f;dash_cool=2.2f;audio::play_sound(SND_WEAPON_WHIR+take(&last_whir_take),{me.x,me.y,me.z},0.9f,0.62f,true,false,0);
            shake=math::max(shake,0.12f);
        }
    }
}
fn bool dash_invulnerable() => dash_t>0;
fn void note_robot_hurt() { since_hurt=0; }

// ---------------------------------------------------------------- robot upgrade visuals (dyn, after weapons)
fn void skills_draw_robot()
{
    if(!upgrades_ready||player<0||player>=vpt::rig_count)return;
    Vec pos;vpt::Quat q;float s;Vec shift;if(!body_frame(&pos,&q,&s,&shift))return;
    int slot=48;
    for(int a=0;a<3;a++) { if(skill[SK_ARMOR]>a) { draw_rigid(wupgrades[UP_ARMOR1+a].asset,body_point(pos,q,s,shift,wupgrades[UP_ARMOR1+a].at),q,s,slot); } else { w_prev_ok[slot]=false; } slot++; }
    if(skill_scanner())
    {
        draw_rigid(wupgrades[UP_MAST].asset,body_point(pos,q,s,shift,wupgrades[UP_MAST].at),q,s,slot);
        vpt::Quat dq=vpt::qmul(q,vpt::qaxis({0,1,0},dish_angle));draw_rigid(wupgrades[UP_DISH].asset,body_point(pos,q,s,shift,wupgrades[UP_DISH].at),dq,s,slot+1);
    }
    else { w_prev_ok[slot]=false;w_prev_ok[slot+1]=false; }
    slot+=2;
    if(skill[SK_AIMBOT]>0) { draw_rigid(wupgrades[UP_OPTIC].asset,body_point(pos,q,s,shift,wupgrades[UP_OPTIC].at),q,s,slot); } else { w_prev_ok[slot]=false; }
    slot++;
    const float[3] CELL_Z={0,0.112f,-0.112f};   // coolant cells: one per regen level along the rear left deck
    for(int c=0;c<3;c++) { if(skill[SK_REGEN]>c) { draw_rigid(wupgrades[UP_CELL].asset,body_point(pos,q,s,shift,wupgrades[UP_CELL].at+(Vec){0,0,CELL_Z[c]}),q,s,slot); } else { w_prev_ok[slot]=false; } slot++; }
    if(skill[SK_DASH]>0)
    {
        draw_rigid(wupgrades[UP_THRUST].asset,body_point(pos,q,s,shift,wupgrades[UP_THRUST].at),q,s,slot);
        if(dash_t>0&&flame_asset>=0)for(int n=0;n<wupgrades[UP_THRUST].anchor_count;n++)
        {
            Vec o=body_point(pos,q,s,shift,wupgrades[UP_THRUST].anchors[n]);Vec back=vpt::qrot(q,{0,0,-1});
            for(int k=0;k<3;k++) { Vec p=o+back*(0.05f+0.07f*(float)k+gr()*0.03f);float fsz=(0.07f-0.015f*(float)k)*s;vpt::Instance it={flame_asset,p[0],p[1],p[2],0,fsz,0};int id=vpt::dyn_add(it,q,k==0?0xffe6b4:0xffb45a,true);vpt::dyn_set_prev(id,it,q); }
            vpt::game_light(o+back*0.2f,{30,50,90},3);
        }
    }
    else { w_prev_ok[slot]=false; }
    // laser designator: a glowing dot where the lock sits (the beam is drawn on the HUD)
    if(skill[SK_AIMBOT]>0&&aim_lock_t>0&&laser_dot_asset>=0)
    {
        vpt::Instance it={laser_dot_asset,aim_lock_p[0],aim_lock_p[1],aim_lock_p[2],0,0.035f,0};int id=vpt::dyn_add(it,vpt::QID);vpt::dyn_set_prev(id,it,vpt::QID);
    }
}
fn Vec optic_lens()
{
    Vec pos;vpt::Quat q;float s;Vec shift;
    if(!upgrades_ready||wupgrades[UP_OPTIC].anchor_count<1||!body_frame(&pos,&q,&s,&shift))return {};
    return body_point(pos,q,s,shift,wupgrades[UP_OPTIC].anchors[0]);
}

// ---------------------------------------------------------------- icons
fn void skills_icons_load()
{
    if(icons_tried)return;icons_tried=true;
    for(int s=0;s<SK_COUNT;s++)
    {
        sk_icon[s]=rl::load_texture(rl::text_format("assets/icons/%s.png",SKILLS[s].icon));
        if(sk_icon[s].id) { rl::gen_texture_mipmaps(&sk_icon[s]);sk_icon[s].set_filter(rl::RLTextureFilter.TRILINEAR); }
    }
    icon_point=rl::load_texture("assets/icons/point.png");icon_lock=rl::load_texture("assets/icons/lock.png");icon_crate=rl::load_texture("assets/icons/crate.png");
    foreach(t:(rl::RLTexture2D*[3]){&icon_point,&icon_lock,&icon_crate})if(t.id) { rl::gen_texture_mipmaps(t);t.set_filter(rl::RLTextureFilter.TRILINEAR); }
}
fn void icon(rl::RLTexture2D t,float x,float y,float size,rl::RLColor tint)
{
    if(!t.id)return;rl::draw_texture_pro(t,{0,0,(float)t.width,(float)t.height},{x,y,size,size},{0,0},0,tint);
}
fn rl::RLColor fade(rl::RLColor c,float a) { c[3]=(char)(int)vpt::clampf((float)c[3]*a,0,255);return c; }
fn rl::RLColor mixc(rl::RLColor a,rl::RLColor b,float t) => {(char)(int)((float)a[0]+((float)b[0]-(float)a[0])*t),(char)(int)((float)a[1]+((float)b[1]-(float)a[1])*t),(char)(int)((float)a[2]+((float)b[2]-(float)a[2])*t),(char)(int)((float)a[3]+((float)b[3]-(float)a[3])*t)};

// ---------------------------------------------------------------- HUD (always): level, XP bar, points, installed skills, dash
fn int skills_hud(int x,int y,rl::RLRectangle view,rl::RLCamera3D cam)
{
    skills_icons_load();
    // laser beam from the optic to the lock (screen space: crisp, no extra geometry)
    if(skill[SK_AIMBOT]>0&&aim_lock_t>0&&!skills_open)
    {
        Vec lens=optic_lens();Vec fwd=nrm(cam.target-cam.position);
        if(vpt::dot(lens-cam.position,fwd)>0.2f&&vpt::dot(aim_lock_p-cam.position,fwd)>0.2f)
        {
            rl::RLVector2 a=rl::get_world_to_screen_ex(lens,cam,(int)view.width,(int)view.height)+(rl::RLVector2){view.x,view.y};
            rl::RLVector2 b=rl::get_world_to_screen_ex(aim_lock_p,cam,(int)view.width,(int)view.height)+(rl::RLVector2){view.x,view.y};
            float k=math::min(1.0f,aim_lock_t/0.15f);
            rl::draw_line_ex(a,b,5,{255,40,30,(char)(int)(50*k)});rl::draw_line_ex(a,b,1.6f,{255,90,70,(char)(int)(210*k)});
            rl::draw_circle((int)b[0],(int)b[1],4,{255,60,40,(char)(int)(230*k)});
        }
    }
    // level badge + XP bar
    float g=level_glow;rl::RLColor gold={250,189,47,255};
    rl::draw_rectangle_rounded({(float)x,(float)y,46,22},0.35f,6,mixc({29,32,33,220},{90,70,20,240},g));
    ui::text(rl::text_format("LV %d",level),x+7,y+4,13,gold);
    int bw=210;rl::draw_rectangle_rounded({(float)x+52,(float)y+7,(float)bw,9},0.5f,4,{29,32,33,220});
    float f=vpt::clampf((float)xp/(float)xp_to_next(level),0,1);
    if(f>0)rl::draw_rectangle_rounded({(float)x+53,(float)y+8,(float)(bw-2)*f,7},0.5f,4,mixc({200,150,40,255},{255,240,170,255},g));
    ui::text(rl::text_format("%d / %d XP",xp,xp_to_next(level)),x+60+bw,y+4,12,ui::MUTED);
    int yy=y+28;
    if(skill_points>0)
    {
        float pulse=0.5f+0.5f*math::sin(skills_time*5);ZString s=rl::text_format("T   %d skill point%s",skill_points,skill_points>1?"s":"");
        int w=ui::text_width(s,13)+40;rl::draw_rectangle_rounded({(float)x,(float)yy,(float)w,24},0.35f,6,mixc({60,48,16,230},{120,90,20,240},pulse));
        rl::draw_rectangle_rounded_lines_ex({(float)x,(float)yy,(float)w,24},0.35f,6,1.5f,fade(gold,0.5f+0.5f*pulse));
        icon(icon_point,(float)x+6,(float)yy+3,18,gold);ui::text(s,x+30,yy+5,13,gold);yy+=30;
    }
    // installed skills: icon chips with level pips
    int cx=x;bool shown=false;
    for(int s=0;s<SK_COUNT;s++)if(skill[s]>0)
    {
        shown=true;rl::RLColor c=BRANCH_COLOR[SKILLS[s].branch];
        rl::draw_rectangle_rounded({(float)cx,(float)yy,30,30},0.3f,6,{29,32,33,215});icon(sk_icon[s],(float)cx+4,(float)yy+3,22,c);
        for(int l=0;l<SKILLS[s].max;l++)rl::draw_rectangle(cx+5+l*7,yy+26,5,2,l<skill[s]?c:(rl::RLColor){80,73,69,255});
        if(s==SK_DASH&&dash_cool>0) { float k=dash_cool/2.2f;rl::draw_rectangle(cx,yy+(int)(30*(1-k)),30,(int)(30*k),{0,0,0,140}); }
        cx+=34;
    }
    if(shown)yy+=36;
    return yy;
}

// ---------------------------------------------------------------- the tree (T): paused, full screen
fn void spark_burst(rl::RLVector2 at,rl::RLColor c,int n)
{
    for(int k=0;k<n;k++) { float a=gr()*6.2832f;float sp=80+gr()*220;sparks[spark_next]={at,{math::cos(a)*sp,math::sin(a)*sp-60},0.5f+gr()*0.4f,c};spark_next=(spark_next+1)%48; }
}
fn rl::RLRectangle node_rect(int s,rl::RLRectangle panel)
{
    const float NODE=86;float colw=panel.width/5.0f;
    float cx=panel.x+colw*(SKILLS[s].col+0.5f)*(5.0f/5.0f);
    float cy=panel.y+150+(float)SKILLS[s].row*150;
    return {cx-NODE/2,cy-NODE/2,NODE,NODE};
}
fn void draw_skill_menu(rl::RLRectangle view)
{
    if(!skills_open)return;
    skills_icons_load();float dt=math::min(rl::get_frame_time(),0.05f);   // the game is paused; the UI animates on real time
    float t=(float)rl::get_time();
    rl::draw_rectangle_rec(view,{8,9,10,205});
    float pw=math::min(view.width-60,1180.0f);float ph=math::min(view.height-60,700.0f);
    rl::RLRectangle panel={view.x+(view.width-pw)/2,view.y+(view.height-ph)/2,pw,ph};
    rl::draw_rectangle_rounded({panel.x+6,panel.y+10,panel.width,panel.height},0.03f,8,{0,0,0,140});
    rl::draw_rectangle_rounded(panel,0.03f,8,{32,30,29,250});rl::draw_rectangle_rounded_lines_ex(panel,0.03f,8,1.5f,{80,73,69,255});
    // header: title, level, XP, points
    int hx=(int)panel.x+28;int hy=(int)panel.y+22;rl::RLColor gold={250,189,47,255};
    ui::text(skills_station?"SKILL STATION":"SKILLS",hx,hy,28,ui::TEXT);
    int lx=hx+(skills_station?250:140);
    ui::text(rl::text_format("LEVEL %d",level),lx,hy+8,16,gold);
    float f=vpt::clampf((float)xp/(float)xp_to_next(level),0,1);
    rl::draw_rectangle_rounded({(float)lx+90,(float)hy+11,220,9},0.5f,4,{20,20,20,255});
    if(f>0)rl::draw_rectangle_rounded({(float)lx+91,(float)hy+12,218*f,7},0.5f,4,{220,170,50,255});
    ui::text(rl::text_format("%d / %d XP",xp,xp_to_next(level)),lx+320,hy+8,13,ui::MUTED);
    {
        ZString ps=rl::text_format("%d",skill_points);int pxr=(int)(panel.x+panel.width)-28;float pulse=skill_points>0?0.5f+0.5f*math::sin(t*4):0;
        int bw=150;rl::draw_rectangle_rounded({(float)(pxr-bw),(float)hy-2,(float)bw,40},0.3f,6,skill_points>0?mixc({70,54,16,255},{120,92,24,255},pulse):(rl::RLColor){40,38,36,255});
        icon(icon_point,(float)(pxr-bw+10),(float)hy+4,28,skill_points>0?gold:ui::MUTED);
        ui::text(ps,pxr-bw+46,hy+4,26,skill_points>0?gold:ui::MUTED);ui::text(skill_points==1?"point":"points",pxr-bw+50+ui::text_width(ps,26),hy+12,13,ui::MUTED);
    }
    // branch headers + column guides
    float colw=panel.width/5.0f;
    for(int b=0;b<BRANCHES;b++)
    {
        float c0=b==0?0:b==1?1:b==2?3:4;float c1=b==0?0:b==1?2:b==2?3:4;
        float x0=panel.x+colw*c0+10;float x1=panel.x+colw*(c1+1)-10;
        rl::draw_rectangle_rounded({x0,panel.y+82,x1-x0,panel.height-150},0.04f,6,fade(BRANCH_COLOR[b],0.05f));
        ZString n=BRANCH_NAMES[b];ui::text(n,(int)((x0+x1)/2)-ui::text_width(n,13)/2,(int)panel.y+90,13,BRANCH_COLOR[b]);
    }
    // links
    for(int s=0;s<SK_COUNT;s++)if(SKILLS[s].req>=0)
    {
        rl::RLRectangle a=node_rect(SKILLS[s].req,panel);rl::RLRectangle b=node_rect(s,panel);
        rl::RLVector2 p0={a.x+a.width/2,a.y+a.height+36};rl::RLVector2 p1={b.x+b.width/2,b.y-6};   // below the pips + name
        bool lit=skill_unlocked(s);rl::RLColor c=lit?BRANCH_COLOR[SKILLS[s].branch]:(rl::RLColor){70,64,60,255};
        rl::RLVector2 m0={p0[0],(p0[1]+p1[1])/2};rl::RLVector2 m1={p1[0],(p0[1]+p1[1])/2};
        rl::draw_line_ex(p0,m0,lit?4:2,c);rl::draw_line_ex(m0,m1,lit?4:2,c);rl::draw_line_ex(m1,p1,lit?4:2,c);
        if(lit) { float u=t*0.8f+(float)s*0.37f;u-=math::floor(u);rl::RLVector2 dot=u<0.5f?p0+(m0-p0)*(u*2):m1+(p1-m1)*((u-0.5f)*2);rl::draw_circle((int)dot[0],(int)dot[1],3,fade(ui::TEXT,0.8f)); }
        // requirement badge on the link
    }
    // nodes
    rl::RLVector2 mouse=rl::get_mouse_position();sk_hover= -1;
    for(int s=0;s<SK_COUNT;s++)
    {
        rl::RLRectangle r=node_rect(s,panel);rl::RLColor bc=BRANCH_COLOR[SKILLS[s].branch];
        bool unlocked=skill_unlocked(s);bool maxed=skill[s]>=SKILLS[s].max;bool can=skill_available(s)&&skill_points>0;
        bool hover=mouse[0]>=r.x&&mouse[0]<=r.x+r.width&&mouse[1]>=r.y&&mouse[1]<=r.y+r.height;if(hover)sk_hover=s;
        float pop=sk_pop[s];float grow=pop*10+(hover?4:0);rl::RLRectangle rr={r.x-grow/2,r.y-grow/2,r.width+grow,r.height+grow};
        if(can) { float pulse=0.5f+0.5f*math::sin(t*4+(float)s);rl::draw_rectangle_rounded({rr.x-6,rr.y-6,rr.width+12,rr.height+12},0.28f,8,fade(bc,0.12f+0.18f*pulse)); }
        rl::RLColor fill=skill[s]>0?mixc({36,34,32,255},bc,0.28f):unlocked?(rl::RLColor){44,41,39,255}:(rl::RLColor){30,29,28,255};
        rl::draw_rectangle_rounded(rr,0.22f,8,fill);
        rl::draw_rectangle_rounded_lines_ex(rr,0.22f,8,maxed?3:can||hover?2.5f:1.5f,maxed?(rl::RLColor){250,189,47,255}:unlocked?bc:(rl::RLColor){70,64,60,255});
        rl::RLColor ic=skill[s]>0?mixc(bc,{255,255,255,255},0.25f+pop*0.6f):unlocked?fade(bc,0.75f):(rl::RLColor){90,84,80,255};
        icon(sk_icon[s],rr.x+rr.width*0.17f,rr.y+rr.height*0.12f,rr.width*0.66f,ic);
        if(!unlocked)icon(icon_lock,rr.x+rr.width-24,rr.y+4,20,{150,140,130,255});
        // level pips under the node
        int pips=SKILLS[s].max;float pwid=(float)pips*16-4;
        for(int l=0;l<pips;l++)rl::draw_rectangle_rounded({r.x+r.width/2-pwid/2+(float)l*16,r.y+r.height+9,12,6},0.5f,4,l<skill[s]?bc:(rl::RLColor){70,64,60,255});
        ZString nm=SKILLS[s].name;ui::text(nm,(int)(r.x+r.width/2)-ui::text_width(nm,13)/2,(int)(r.y+r.height)+20,13,skill[s]>0?ui::TEXT:unlocked?ui::MUTED:(rl::RLColor){110,102,96,255});
        if(maxed)ui::text("MAX",(int)(r.x+r.width)-30,(int)r.y-14,11,{250,189,47,255});
        if(hover&&rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
        {
            if(skill_install(s,false)) { spark_burst({r.x+r.width/2,r.y+r.height/2},bc,22); }
            else { audio::play_sound(SND_WEAPON_LATCH,{},0.3f,0.7f,false,false,0); }
        }
    }
    // sparks
    for(int k=0;k<48;k++)if(sparks[k].t>0) { UiSpark* sp=&sparks[k];sp.t-=dt;sp.p+=sp.v*dt;sp.v[1]+=500*dt;rl::draw_rectangle((int)sp.p[0],(int)sp.p[1],4,4,fade(sp.c,math::min(1.0f,sp.t*2))); }
    // info card for the hovered node (else a hint)
    int ix=(int)panel.x+28;int iy=(int)(panel.y+panel.height)-62;
    if(sk_hover>=0)
    {
        int s=sk_hover;SkillDef d=SKILLS[s];rl::RLColor bc=BRANCH_COLOR[d.branch];
        rl::RLRectangle r=node_rect(s,panel);float cw=330;float chh=40+(float)d.max*22+56;
        float cxp=r.x+r.width+18;if(cxp+cw>panel.x+panel.width-10)cxp=r.x-cw-18;float cyp=math::min(r.y-10,panel.y+panel.height-chh-80);
        rl::draw_rectangle_rounded({cxp+4,cyp+6,cw,chh},0.08f,6,{0,0,0,150});rl::draw_rectangle_rounded({cxp,cyp,cw,chh},0.08f,6,{24,23,22,250});
        rl::draw_rectangle_rounded_lines_ex({cxp,cyp,cw,chh},0.08f,6,1.5f,bc);
        ui::text(d.name,(int)cxp+14,(int)cyp+12,18,ui::TEXT);ui::text(BRANCH_NAMES[d.branch],(int)(cxp+cw)-14-ui::text_width(BRANCH_NAMES[d.branch],11),(int)cyp+16,11,bc);
        for(int l=0;l<d.max;l++)
        {
            bool have=l<skill[s];bool next=l==skill[s];int ly=(int)cyp+44+l*22;
            rl::draw_rectangle((int)cxp+14,ly+5,8,8,have?bc:next?fade(bc,0.45f):(rl::RLColor){70,64,60,255});
            ui::text(d.max>1?rl::text_format("L%d  %s",l+1,d.level_text[l]):d.level_text[l],(int)cxp+30,ly,13,have?ui::TEXT:next?mixc(ui::MUTED,ui::TEXT,0.5f):(rl::RLColor){120,112,104,255});
        }
        int dy=(int)cyp+48+d.max*22;
        // description, wrapped to ~42 chars
        String ds=d.desc.str_view();int start=0;int last_space= -1;int line=0;char[96] buf;
        for(int k=0;k<=(int)ds.len&&line<2;k++)
        {
            bool end=k==(int)ds.len;if(!end&&ds[k]==' ')last_space=k;
            if(end||k-start>44) { int cut=end?k:(last_space>start?last_space:k);int n=math::min(cut-start,95);for(int q=0;q<n;q++)buf[q]=ds[start+q];buf[n]=0;ui::text((ZString)&buf[0],(int)cxp+14,dy+line*18,12,ui::MUTED);line++;start=cut+1;last_space= -1;if(end)break; }
        }
        ZString act=skill[s]>=d.max?"fully installed":!skill_unlocked(s)?rl::text_format("needs %s level %d",SKILLS[d.req].name,d.req_level):skill_points>0?"click: install (1 point)":"no skill points - level up or open crates";
        ui::text(act,(int)cxp+14,(int)(cyp+chh)-22,12,skill[s]>=d.max?gold:!skill_unlocked(s)?ui::BAD:skill_points>0?gold:ui::MUTED);
    }
    else
    {
        ZString hint=skill_points>0?"click a glowing skill to install it":"kill creatures for XP; crates install a free random skill";
        ui::text(hint,ix,iy+18,14,ui::MUTED);
    }
    // footer: station respec / close
    int fx=(int)(panel.x+panel.width)-28;
    ui::text("T / Esc  close",fx-ui::text_width("T / Esc  close",13),iy+20,13,ui::MUTED);
    if(skills_station)
    {
        bool can=!station_respec_used;int bx=fx-360;
        if(can) { if(ui::button("Respec (once)",bx,iy+12,170))skills_respec(); }
        else { ui::text("respec used",bx+30,iy+20,13,ui::MUTED); }
    }
}
