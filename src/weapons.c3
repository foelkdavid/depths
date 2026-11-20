module depths;
import std::math;
import std::encoding::json;
import raylib6::rl;
import vpt;

// Three swappable weapons on the robot's nose hardpoint (keys 1/2/3). The models are voxel attachments
// written by build-hexapod.js (maintenance-hexapod.weapons.json: hinge, each piece's rest origin, muzzles,
// all in rig space). Each frame the pieces are posed from the body part's live transform, so they follow
// look pitch, bob and bank; shots leave the actual muzzles. Everything moving is procedural:
//   swap: the old weapon folds down under the nose, the new one swings up with an overshoot + settle wobble
//   MG: barrels recoil alternately   rocket: pod lifts and shudders through the windup, heavy kick on launch
//   shotgun: muzzle kick, then the pump racks back and forward   all: weapon pitches toward the aim point
const int W_MG=0;const int W_ROCKET=1;const int W_SHOTGUN=2;const int WEAPON_COUNT=3;
const ZString[WEAPON_COUNT] WEAPON_NAMES={"MACHINE GUN","ROCKETS","SHOTGUN"};
const float FOLD_ANGLE=1.75f;   // stowed: ~100 deg down under the nose
const float FOLD_DOWN_TIME=0.2f;const float FOLD_UP_TIME=0.34f;

struct WeaponPartFile { String asset;String role;float[] at; }
struct WeaponFile { String name;WeaponPartFile[] parts;float[][] muzzles; }
struct MultiFile { float[] guns;String asset;float[] at; }
struct MountFile { String name;int fold;float[] hinge;WeaponPartFile[] parts;MultiFile[] multi; }
struct UpgradeFile { String name;String asset;float[] at;float[][] anchors; }
struct WeaponsFile { int version;float[] hinge;WeaponFile[] weapons;MountFile[] mounts;UpgradeFile[] upgrades; }
struct WPart { int asset;int role;Vec at; }   // role 0 base, 1 barrel (recoils, by index), 2 pump
struct WModel { WPart[4] parts;int part_count;Vec[6] muzzles;int muzzle_count;bool pump; }
// Player mechs (ROBOT_RIGS, chosen in the main menu): each carries ONE weapon from its own
// <rig>.weapons.json. The Rattler's file still holds all three (tests swap them); the others hold one + a fixed mount.
const ZString[ROBOT_COUNT] ROBOT_NAMES={"HX-6  RATTLER","BR-4  MORTAR","CQ-1  MAUL"};
const ZString[ROBOT_COUNT] ROBOT_ROLES={"machine gun  /  quick","rocket artillery  /  slow, heavy","double-barrel shotgun  /  fastest"};
const int[ROBOT_COUNT] ROBOT_WEAPON={W_MG,W_ROCKET,W_SHOTGUN};
const float[ROBOT_COUNT] ROBOT_SPEED={1.05f,1,1};      // on top of each rig's anim speed (Rattler: 5 % quicker than the MH-6 was)
const float[ROBOT_COUNT] ROBOT_GRIP={0.45f,0.62f,0.42f};   // body radius for wall collision
fn int robot_index(int def)
{
    if(def<0||def>=vpt::rig_def_count)return -1;String n=((ZString)&vpt::rig_defs[def].name[0]).str_view();
    for(int k=0;k<ROBOT_COUNT;k++)if(n==ROBOT_RIGS[k].str_view())return k;
    return -1;
}
fn int robot_of(int r) => r>=0&&r<vpt::rig_count?math::max(0,robot_index(vpt::rigs[r].def)):0;
bool[WEAPON_COUNT] wmodel_ok;int mount_count=2;
// Three takes per mechanical sound; never the same one twice in a row.
int last_shotgun_take= -1;int last_whir_take= -1;int last_latch_take= -1;
fn int take(int* last) { int k=(int)(gr_servo()*2.99f);if(k==*last)k=(k+1+(int)(gr_servo()*1.99f))%3;*last=k;return k; }
WModel[WEAPON_COUNT] wmodels;Vec w_hinge;bool weapons_ready;
// Mounts (F3): 0 under the nose (folds down), 1 on a deck pylon (folds up and back). Weapons are authored
// around the under hinge; on the top mount they are translated to its hinge. Top is the default.
const int MOUNT_UNDER=0;const int MOUNT_TOP=1;
struct WMount { Vec hinge;float fold;WPart part;WPart[3] multi;float[3][3] guns; }   // multi[n-1]: yoke for n guns, guns[n-1][g]: x offset (m)
// Skill upgrades riding on the body (armor plates, scanner, optic, coolant cells, thrusters) + effect anchors.
const int UP_ARMOR1=0;const int UP_ARMOR2=1;const int UP_ARMOR3=2;const int UP_MAST=3;const int UP_DISH=4;const int UP_OPTIC=5;const int UP_CELL=6;const int UP_THRUST=7;const int UP_COUNT=8;
const ZString[UP_COUNT] UP_NAMES={"armor-1","armor-2","armor-3","scanner-mast","scanner-dish","optic","coolant-cell","thrusters"};
struct WUpgrade { int asset;Vec at;Vec[2] anchors;int anchor_count; }
WUpgrade[UP_COUNT] wupgrades;bool upgrades_ready;
WMount[2] wmounts;int weapon_mount=MOUNT_TOP;int mount_pending= -1;int rocket_round_asset= -1;

int weapon;int weapon_pending= -1;int swap_stage;float swap_t;   // stage 0 ready, 1 folding down, 2 swinging up
float w_kick;float w_kick_v;float w_aim;float w_lift;float w_roll;
float[2] w_barrel;float w_pump;float w_pump_t= -1;
vpt::Instance[64] w_prev;vpt::Quat[64] w_prev_q;bool[64] w_prev_ok;   // 0..35 gun*12+weapon*4+part, 36..41 mount yokes, 48.. upgrades

fn Vec vec3_of(float[] v) => v.len==3?(Vec){v[0],v[1],v[2]}:(Vec){};
fn int weapon_asset(String rel)
{
    if(rel.len>=400)return -1;char[512] path;ZString pre="assets/library/BLACK_START/";int n=0;
    foreach(c:pre.str_view())path[n++]=c;foreach(c:rel)path[n++]=c;path[n]=0;
    int id=vpt::import_asset((ZString)&path[0]);if(id>=0)vpt::pinned_assets[id]=true;return id;
}
// F3: fold the weapon away, move to the other mount, swing it up there.
fn void weapon_toggle_mount()
{
    if(!weapons_ready||mount_count<2||rocket_charge>0||swap_stage!=0)return;
    mount_pending=1-weapon_mount;weapon_pending=weapon;swap_stage=1;swap_t=0;
    audio::play_sound(SND_WEAPON_WHIR+take(&last_whir_take),muzzle(0),0.6f,1.05f*jitter(0.05f),true,false,0);
    popup_title=mount_pending==MOUNT_TOP?"TOP MOUNT":"NOSE MOUNT";popup_info="F3 switches the weapon mount";popup_color=0x50c8ff;popup_t=POPUP_TIME*0.6f;
}
fn bool weapons_load()
{
    weapons_ready=false;
    int robot=robot_of(player);
    char* text=rl::load_file_text(rl::text_format("assets/library/BLACK_START/%s.weapons.json",ROBOT_RIGS[robot]));if(!text)return false;
    defer rl::unload_file_text((ZString)text);
    WeaponsFile wf;if(try parsed=json::unmarshal(tmem,((ZString)text).str_view(),WeaponsFile)) { wf=parsed; } else { return false; }
    if(!wf.weapons.len||wf.hinge.len!=3)return false;
    w_hinge=vec3_of(wf.hinge);wmodel_ok={};
    foreach(f:wf.weapons)
    {
        int w=f.name=="mg"?W_MG:f.name=="rocket"?W_ROCKET:f.name=="shotgun"?W_SHOTGUN:-1;if(w<0)continue;
        WModel* m=&wmodels[w];*m={};
        foreach(p:f.parts)
        {
            if(m.part_count>=4||p.asset.len>=400)return false;
            int id=weapon_asset(p.asset);if(id<0)return false;
            m.parts[m.part_count++]={id,p.role=="barrel"?1:p.role=="pump"?2:0,vec3_of(p.at)};if(p.role=="pump")m.pump=true;
        }
        foreach(mz:f.muzzles)if(m.muzzle_count<6)m.muzzles[m.muzzle_count++]=vec3_of(mz);
        if(!m.muzzle_count)return false;wmodel_ok[w]=true;
    }
    if(!wmodel_ok[ROBOT_WEAPON[robot]])return false;
    mount_count=(int)wf.mounts.len;if(mount_count<1||mount_count>2)return false;
    for(int k=0;k<mount_count;k++)
    {
        MountFile mf=wf.mounts[k];if(mf.parts.len!=1||mf.hinge.len!=3)return false;
        int id=weapon_asset(mf.parts[0].asset);if(id<0)return false;
        wmounts[k]={vec3_of(mf.hinge),(float)mf.fold,{id,3,vec3_of(mf.parts[0].at)},{},{}};
        for(int n=0;n<3;n++)
        {
            wmounts[k].multi[n]=wmounts[k].part;wmounts[k].guns[n]={};
            if(n<(int)mf.multi.len&&mf.multi[n].guns.len==(usz)(n+1))
            {
                int mid=weapon_asset(mf.multi[n].asset);if(mid<0)return false;
                wmounts[k].multi[n]={mid,3,vec3_of(mf.multi[n].at)};for(int g=0;g<=n;g++)wmounts[k].guns[n][g]=mf.multi[n].guns[g];
            }
        }
    }
    if(mount_count==1)wmounts[1]=wmounts[0];
    upgrades_ready=false;
    if(wf.upgrades.len>=UP_COUNT)
    {
        upgrades_ready=true;
        for(int u=0;u<UP_COUNT;u++)
        {
            wupgrades[u]={-1,{},{},0};
            foreach(uf:wf.upgrades)if(uf.name==UP_NAMES[u].str_view())
            {
                wupgrades[u].asset=weapon_asset(uf.asset);wupgrades[u].at=vec3_of(uf.at);
                foreach(an:uf.anchors)if(wupgrades[u].anchor_count<2)wupgrades[u].anchors[wupgrades[u].anchor_count++]=vec3_of(an);
            }
            if(wupgrades[u].asset<0)upgrades_ready=false;
        }
    }
    rocket_round_asset=weapon_asset("parts-hexapod/projectile-rocket.vpt.json");
    weapon=ROBOT_WEAPON[robot];weapon_mount=mount_count>1?MOUNT_TOP:0;weapon_pending= -1;mount_pending= -1;swap_stage=0;swap_t=0;w_kick=0;w_kick_v=0;w_aim=0;w_lift=0;w_roll=0;w_barrel={};w_pump=0;w_pump_t= -1;w_prev_ok={};
    weapons_ready=true;return true;
}
fn void weapon_select(int w)
{
    if(!weapons_ready||w<0||w>=WEAPON_COUNT||!wmodel_ok[w]||rocket_charge>0)return;
    if(mount_pending>=0)return;
    if(swap_stage==0&&w==weapon)return;
    if(swap_stage==2&&w==weapon)return;
    weapon_pending=w;
    if(swap_stage==0||swap_stage==2)
    {
        // Fold from wherever the current weapon is (a swing-up can be reversed mid-way).
        float now=swap_stage==2?weapon_fold_amount():0;swap_stage=1;swap_t=now*FOLD_DOWN_TIME;
        Vec m=muzzle(0);audio::play_sound(SND_WEAPON_WHIR+take(&last_whir_take),m,0.6f,1.12f*jitter(0.05f),true,false,0);
    }
}
fn bool weapon_ready() => !weapons_ready||swap_stage==0||(swap_stage==2&&swap_t>FOLD_UP_TIME*0.85f);
fn float ease_out_back(float t) { float c=1.9f;float u=t-1;return 1+(c+1)*u*u*u+c*u*u; }
// 0 deployed .. 1 stowed (may dip below 0: the overshoot as the weapon slams into place).
fn float weapon_fold_amount()
{
    if(swap_stage==1) { float u=vpt::clampf(swap_t/FOLD_DOWN_TIME,0,1);return u*u*u; }
    if(swap_stage==2) { float u=vpt::clampf(swap_t/FOLD_UP_TIME,0,1);return 1-ease_out_back(u); }
    return 0;
}
fn void weapon_update(float dt)
{
    if(!weapons_ready)return;
    if(swap_stage==1)
    {
        swap_t+=dt;
        if(swap_t>=FOLD_DOWN_TIME)
        {
            weapon=weapon_pending;weapon_pending= -1;if(mount_pending>=0) { weapon_mount=mount_pending;mount_pending= -1; }swap_stage=2;swap_t=0;w_barrel={};w_pump=0;w_pump_t= -1;
            Vec m=muzzle(0);audio::play_sound(SND_WEAPON_WHIR+take(&last_whir_take),m,0.62f,0.94f*jitter(0.05f),true,false,0);
        }
    }
    else if(swap_stage==2)
    {
        float before=swap_t;swap_t+=dt;
        if(before<FOLD_UP_TIME*0.62f&&swap_t>=FOLD_UP_TIME*0.62f)   // the moment it slams past horizontal: latch
        { Vec m=muzzle(0);audio::play_sound(SND_WEAPON_LATCH+take(&last_latch_take),m,0.7f,jitter(0.05f),true,false,0);w_kick_v-=1.6f;shake=math::max(shake,0.06f); }
        if(swap_t>=FOLD_UP_TIME)swap_stage=0;
    }
    // A damped spring for the pitch kick; barrels and pump ease back.
    float k=260;float c=2*math::sqrt(k)*0.55f;w_kick_v+=(-k*w_kick-c*w_kick_v)*dt;w_kick+=w_kick_v*dt;
    for(int b=0;b<2;b++)w_barrel[b]*=math::exp(-dt*16);
    if(w_pump_t>=0)
    {
        float before=w_pump_t;w_pump_t+=dt;
        // rack: wait, pull back, push forward (clink at both ends)
        float t=w_pump_t-0.1f;w_pump=t<0?0:t<0.11f?t/0.11f:t<0.27f?1-(t-0.11f)/0.16f:0;
        if(before<0.21f&&w_pump_t>=0.21f) { audio::play_sound(SND_WEAPON_LATCH+take(&last_latch_take),muzzle(0),0.42f,1.3f*jitter(0.04f),true,false,0); }
        if(before<0.37f&&w_pump_t>=0.37f) { audio::play_sound(SND_WEAPON_LATCH+take(&last_latch_take),muzzle(0),0.5f,1.55f*jitter(0.04f),true,false,0);w_pump_t= -1;w_pump=0; }
    }
    // Rocket windup: the pod tips up and shudders until the launch.
    float lift_target=weapon==W_ROCKET&&rocket_charge>0?-0.13f+(gr()-0.5f)*0.03f:0;w_lift+=(lift_target-w_lift)*math::min(1.0f,dt*12);
    // Swing-up wobble about the barrel axis, decaying.
    w_roll=swap_stage==2?0.16f*math::exp(-swap_t*9)*math::sin(swap_t*38):w_roll*math::exp(-dt*10);
    // Pitch toward the aim point (the chassis does the coarse aiming; this is the last few degrees).
    if(player>=0&&player<vpt::rig_count&&vpt::rigs[player].has_look_point)
    {
        Vec pos;vpt::Quat q;float s;Vec shift;
        if(body_frame(&pos,&q,&s,&shift))
        {
            Vec h=body_point(pos,q,s,shift,mount_hinge());Vec d=vpt::qrot(vpt::qconj(q),vpt::rigs[player].look_point-h);
            float want=vpt::clampf(math::atan2(-d[1],math::max(0.2f,d[2])),-0.4f,0.4f);w_aim+=(want-w_aim)*math::min(1.0f,dt*14);
        }
    }
}
// Called by fire_shot / fire_shell once the shot left muzzle `b`.
fn void weapon_fired(int b)
{
    if(!weapons_ready)return;
    if(weapon==W_MG) { w_barrel[b&1]=0.045f;w_kick_v-=0.9f; }
    else if(weapon==W_ROCKET) { w_kick_v-=6.5f;w_lift=0; }
    else if(wmodels[weapon].pump) { w_kick_v-=5.0f;w_pump_t=0; }
    else { w_kick_v-=5.5f;w_barrel[b&1]=0.07f; }   // double barrel: the fired barrel slams back
}
fn bool body_frame(Vec* pos,vpt::Quat* q,float* scale,Vec* shift)
{
    if(player<0||player>=vpt::rig_count)return false;int k=first_part(player);
    if(k<0||k>=vpt::rig_part_count||vpt::rig_part_owner[k]!=player)return false;vpt::Instance b=vpt::rig_parts[k];
    *q=vpt::qmul(vpt::qaxis({0,1,0},b.rotation),vpt::rig_part_q[k]);*pos={b.x,b.y,b.z};*scale=b.scale;
    *shift=vpt::rig_defs[vpt::rigs[player].def].parts[0].shift;return true;
}
// Rest rig-space point -> world through the body part's current pose.
fn Vec body_point(Vec pos,vpt::Quat q,float s,Vec shift,Vec p) => pos+vpt::qrot(q,p-shift)*s;
// Hinge rotation for the current state: fold + kick + aim + windup lift, plus the settle roll.
fn vpt::Quat weapon_pose()
{
    float fold=weapon_fold_amount();float pitch=FOLD_ANGLE*wmounts[weapon_mount].fold*fold+(w_kick+w_lift+w_aim)*(1-vpt::clampf(fold,0,1));
    return vpt::qmul(vpt::qaxis({0,0,1},w_roll),vpt::qaxis({1,0,0},pitch));
}
// Weapons are authored around the under-nose hinge: translate to the active mount's hinge, then rotate about it.
fn Vec mount_hinge() => weapons_ready?wmounts[weapon_mount].hinge:w_hinge;
fn Vec weapon_posed(vpt::Quat f,Vec p,int g=0) => mount_hinge()+vpt::qrot(f,p+(Vec){gun_offset(g),0,0}-w_hinge);
// Multi-gun skill: 1-3 guns side by side on one hinge axis (offsets from the generator, per mount).
fn int gun_count() => weapons_ready?math::clamp(1+skill[SK_MULTI],1,3):1;
fn float gun_offset(int g) { int n=gun_count();return weapons_ready&&g>=0&&g<n?wmounts[weapon_mount].guns[n-1][g]:0; }
// World muzzle of barrel b of the current weapon (legacy twin-cannon point when the models are missing).
fn Vec weapon_muzzle(int b,int g=-1)
{
    Vec pos;vpt::Quat q;float s;Vec shift;
    if(!weapons_ready||!body_frame(&pos,&q,&s,&shift))return {};
    if(g<0)g=gun_count()==2?0:gun_count()/2;   // aim/sound reference: the centre gun (left of a pair)
    WModel* m=&wmodels[weapon];return body_point(pos,q,s,shift,weapon_posed(weapon_pose(),m.muzzles[b%m.muzzle_count],g));
}
fn int weapon_muzzles() => weapons_ready?wmodels[weapon].muzzle_count:2;
fn void weapons_draw()
{
    if(!weapons_ready||player<0||player>=vpt::rig_count)return;
    Vec pos;vpt::Quat q;float s;Vec shift;if(!body_frame(&pos,&q,&s,&shift))return;
    vpt::Quat f=weapon_pose();vpt::Quat wq=vpt::qmul(q,f);WModel* m=&wmodels[weapon];
    int guns=gun_count();
    {
        // the mount (a wider yoke for several guns) rides rigidly on the body
        WPart mp=wmounts[weapon_mount].multi[guns-1];int slot=36+weapon_mount*3+guns-1;
        for(int k=36;k<42;k++)if(k!=slot)w_prev_ok[k]=false;
        draw_rigid(mp.asset,body_point(pos,q,s,shift,mp.at),q,s,slot);
    }
    for(int g=0;g<guns;g++)for(int i=0;i<m.part_count;i++)
    {
        if(g>0&&gun_offset(g)==gun_offset(0))continue;   // a fixed mount without multi-gun yokes: extra guns share the one model
        WPart p=m.parts[i];Vec at=p.at;
        if(p.role==1)at[2]-=w_barrel[(i==1?0:1)^(g&1)];   // barrel0 is part 1, barrel1 part 2: alternate recoil (mirrored per gun)
        if(p.role==2)at[2]-=w_pump*0.05f;
        draw_rigid(p.asset,body_point(pos,q,s,shift,weapon_posed(f,at,g)),wq,s,g*12+weapon*4+i);
    }
    for(int g=0;g<3;g++)for(int w=0;w<WEAPON_COUNT;w++)if(w!=weapon||g>=guns)for(int i=0;i<4;i++)w_prev_ok[g*12+w*4+i]=false;
}
// One rigid dyn piece with its previous transform (motion vectors), remembered in slot.
fn void draw_rigid(int asset,Vec o,vpt::Quat q,float s,int slot)
{
    vpt::Instance it={asset,o[0],o[1],o[2],0,s,0};int id=vpt::dyn_add(it,q);if(id<0)return;
    if(w_prev_ok[slot]) { vpt::dyn_set_prev(id,w_prev[slot],w_prev_q[slot]); } else { vpt::dyn_set_prev(id,it,q); }
    w_prev[slot]=it;w_prev_q[slot]=q;w_prev_ok[slot]=true;
}
fn void weapons_hud(int x,int y)
{
    // the mech and its one weapon (chosen in the main menu)
    int k=robot_of(player);ZString label=rl::text_format("%s   %s",ROBOT_NAMES[k],WEAPON_NAMES[weapon]);int width=ui::text_width(label,12)+18;
    rl::draw_rectangle_rounded({(float)x,(float)y,(float)width,22},0.3f,4,(rl::RLColor){60,52,30,235});
    rl::draw_rectangle(x+4,y+18,width-8,2,ui::ACCENT);ui::text(label,x+9,y+5,12,ui::ACCENT);
}
