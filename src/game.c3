module depths;
import std::math;
import std::io;
import raylib6::rl;
import vpt;

// ---- "Depths": a twin-stick shooter that runs inside the editor's play mode.
// Possess the robot (select it, P): WASD walks, the mouse aims the whole body (flashlight + twin cannon),
// left mouse fires. Creatures hunt you, everything reacts to hits and bursts into its own voxels on death.
// Scenes with a "game" layout (build-depths.py) add Isaac-style rooms: doors lock while a room's
// creatures live and open when it is cleared. Stopping play restores the scene (one undo step).
// Nothing here runs unless a hexapod rig is being played, so the editor is unaffected.
alias Vec=rl::RLVector3;

const int NONE=0;const int SKITTER=1;const int CRAWLER=2;const int NEST=3;const int PLAYER=4;const int BLOATER=5;const int FLUTTER=6;const int SCAVENGER=7;const int STALKER=8;
bool game_on;
bool game_over;
bool layer_clear;
int player= -1;
int player_home= -1;   // the robot's rig index when the run started (restart re-possesses it)
float gate_scale=1;
float player_hp;
float hurt;           // red flash 0..1
float shake;
float fire_cool;
int barrel;
// BR-4 Mortar: every launch shoves the whole mech back and bogs it down for a moment (the price of the blast).
const float HEAVY_TIME=0.75f;float heavy_t;
// Modifiers (items): on/off. A duplicate pickup turns into one you don't have yet (or repairs you).
const int MOD_SPREAD=0;const int MOD_ROCKET=1;const int MOD_VISION=2;const int MOD_OVERCLOCK=3;const int MOD_PIERCE=4;const int MOD_RICOCHET=5;const int MOD_NANITES=6;const int MOD_SERVO=7;const int MOD_COUNT=8;
// MOD_* survive only as legacy item kinds in saved scenes: every non-key pickup is now a free perk (skills.c3).
const uint PERK_COLOR=0x2fbdfa;   // 0xBBGGRR gold
bool god;
bool auto_aim;
int last_foot;int last_shot;float rocket_charge;int rocket_voice= -1;
const float ROCKET_WINDUP=0.43f;   // seconds into missile_launch.wav where the bang is (the rocket leaves)
const float ROCKET_PITCH=0.8f;     // played slower/deeper: a heavy launcher
struct DamageText { Vec p;float v;float t; }
DamageText[10] dmg_texts;int dmg_text_next;
// Hit feedback on creatures: white flash on the struck rig (vpt::rig_hit_flash), a health bar that shows for a
// while after a hit, merged damage numbers (a shotgun shell reads as one number), and a hit marker + tick.
struct HitText { Vec p;float v;float t;int rig;bool kill;int xp; }
HitText[16] hit_texts;int hit_text_next;
float[vpt::MAX_RIGS] hp_max;float[vpt::MAX_RIGS] bar_t;float[vpt::MAX_RIGS] bar_shown;
float marker_t;bool marker_kill;Vec marker_p;float tick_time= -1;
fn Vec rig_top(int r) { vpt::Rig* e=&vpt::rigs[r];Vec up=e.oriented?(Vec){e.up[0],e.up[1],e.up[2]}:(Vec){0,1,0};return (Vec){e.x,e.y,e.z}+up*(0.85f*e.scale); }
fn void note_enemy_hit(int r,Vec point,float dmg,bool pellet)
{
    vpt::rig_hit_flash[r]=math::max(vpt::rig_hit_flash[r],pellet?0.75f:1.0f);bar_t[r]=3;marker_t=0.22f;marker_kill=false;marker_p=point;
    // merge into this rig's live number (pellets of one shell, MG bursts) instead of a cloud of digits
    for(int i=0;i<16;i++) { HitText* h=&hit_texts[i];if(h.t>0.55f&&h.rig==r&&!h.kill) { h.v+=dmg;h.t=math::max(h.t,0.85f);return; } }
    hit_texts[hit_text_next]={rig_top(r)+(Vec){(gr()-0.5f)*0.3f,0.5f,(gr()-0.5f)*0.3f},dmg,0.9f,r,false,0};hit_text_next=(hit_text_next+1)%16;
    if(game_time-tick_time>0.07f) { tick_time=game_time;audio::play_sound(SND_WEAPON_LATCH+gr_servo_int(3),point,0.32f,2.3f+gr()*0.2f,false,false,0); }
}
fn void note_enemy_kill(int r,int gx=0)
{
    marker_t=0.38f;marker_kill=true;bar_t[r]=0;bool shown=false;
    for(int i=0;i<16;i++)if(hit_texts[i].rig==r&&hit_texts[i].t>0) { hit_texts[i].kill=true;hit_texts[i].t=1.1f;hit_texts[i].rig= -1;hit_texts[i].xp=gx;shown=true; }
    if(!shown) { hit_texts[hit_text_next]={rig_top(r)+(Vec){0,0.5f,0},0,1.1f,-1,true,gx};hit_text_next=(hit_text_next+1)%16; }
    audio::play_sound(SND_WEAPON_LATCH+gr_servo_int(3),{vpt::rigs[r].x,vpt::rigs[r].y,vpt::rigs[r].z},0.55f,1.45f,false,false,0);
}
const float POPUP_TIME=2.8f;float popup_t;ZString popup_title;ZString popup_info;uint popup_color;   // item pickup toast
int[vpt::MAX_RIGS] crawl_voice;int[12] step_phase;   // crawl_voice: looping crawl per creature rig (-1 none); step_phase: robot gait phase (foot landings)
bool cheat_open;
rl::RLRectangle cheat_rect;
struct Pickup { float x;float z;int kind;bool taken; }
Pickup[24] pickups;
int pickup_count;
fn void add_pickup(float x,float z,int k) { if(pickup_count<24)pickups[pickup_count++]={x,z,k,false}; }
float game_time;
int[vpt::MAX_RIGS] kind;
float[vpt::MAX_RIGS] hp;
float[vpt::MAX_RIGS] attack_cool;
float[vpt::MAX_RIGS] spawn_cool;
float[vpt::MAX_RIGS] flinch;
float[vpt::MAX_RIGS] fuse;
float[vpt::MAX_RIGS] rush;
// Brood homes are positions, not rig indices: removal swaps rig slots.
struct BroodMind { Vec home;float think;float suspicion;float scatter;float leap;bool alarm;Vec perch;Vec normal;float chirp;float flight;int activity;float temperament;float memory;Vec interest; }
BroodMind[vpt::MAX_RIGS] brood;
int stat_hatches;int stat_brood_bursts;int stat_leaps;int stat_surface_skitters;int stat_flights;
bool[vpt::MAX_RIGS] aware;   // has noticed the robot (sight within 22 m, closer than 4 m, or got shot); until then it idles/wanders   // crawler: seconds of rushing left (refreshed while it sees the robot)   // bloater: < 0 idle, else seconds until it detonates
// Bloater detonations are queued (kill_rig must not recurse into explode(), and chains read better staggered).
struct Blast { Vec p;float t; }
Blast[24] blasts;int blast_count;
const float BLAST_RADIUS=3.8f;const float BLAST_DAMAGE=38;
float[vpt::MAX_INSTANCES] prop_hp;
int[vpt::MAX_INSTANCES] prop_full;   // carvable props: voxel count when the game started (breach / collapse thresholds)
int skitter_def= -1;
int cube_asset= -1;
int bolt_asset= -1;int pellet_asset= -1;
int gate_asset= -1;
float saved_tilt;
float saved_zoom;
// rooms
int current_room= -1;
bool[MAX_GAME_ROOMS] room_clear;
bool[MAX_GAME_ROOMS] room_locked;
float[128] door_open;   // 0 closed .. 1 sunk into the floor

struct Bolt { Vec p;Vec prev;Vec v;float life;float dmg;float size;int rocket;int pierce;int bounces;bool pellet; }
const int MAX_BOLTS=96;
const float ROCKET_SPEED=25;const float PELLET_SPEED=80;   // rockets a touch faster than the old 22; pellets are near-hitscan streaks
Bolt[MAX_BOLTS] bolts;
int bolt_count;
struct Debris { Vec p;Vec prev;Vec v;vpt::Quat q;vpt::Quat prev_q;Vec spin;float size;uint color;float floor;bool rest;float glow;float life; }   // life: seconds left, shrinks away over the last 0.6 s
const int MAX_DEBRIS=330;
Debris[MAX_DEBRIS] debris;
int debris_count;
int debris_next;
struct Flash { Vec p;Vec color;float range;float life;float total; }
Flash[16] flashes;
int flash_count;
uint grng=0x2545F491u;
fn float gr() { grng^=grng<<13;grng^=grng>>17;grng^=grng<<5;return (float)(grng&0xffffff)/16777216.0f; }
fn Vec rand_dir() { float z=gr()*2-1;float a=gr()*6.2831853f;float s=math::sqrt(math::max(0.0f,1-z*z));return {math::cos(a)*s,z,math::sin(a)*s}; }
fn Vec nrm(Vec v) { float l=math::sqrt(vpt::dot(v,v));return l>1e-6f?v/l:(Vec){0,0,1}; }

fn bool def_named(int def,String part) => ((ZString)&vpt::rig_defs[def].name[0]).str_view().contains(part);
fn bool is_player_rig(int r) => r>=0&&r<vpt::rig_count&&robot_index(vpt::rigs[r].def)>=0;   // any of the three mechs

// Colonies hatch even off-screen. Leave seven rig slots for a destroyed nest's emergency brood.
fn Vec brood_home(Vec p)
{
    Vec home=p;float best=144;
    for(int n=0;n<vpt::rig_count;n++)if(kind[n]==NEST)
    {
        vpt::Rig* nest=&vpt::rigs[n];Vec q={nest.x,nest.y,nest.z};Vec dv=q-p;dv[1]=0;
        float ds=vpt::dot(dv,dv);if(ds<best) { best=ds;home=q; }
    }
    return home;
}
fn void alarm_brood()
{
    for(int k=0;k<vpt::rig_count;k++)if(kind[k]==SKITTER||kind[k]==NEST)
    { aware[k]=true;brood[k].alarm=true;brood[k].scatter=0;brood[k].think=0; }
}
fn bool brood_sees(vpt::Rig* e,Vec target)
{
    Vec eye=vpt::rig_to_world(e,{0,0.35f,0});Vec dv=target-eye;float dl=math::sqrt(vpt::dot(dv,dv));
    if(dl<0.05f)return true;
    vpt::Pick h=vpt::world_pick({eye,dv/dl});return !h.hit||h.distance>dl-0.35f;
}
fn void settle_brood(int r,Vec home)
{
    vpt::Rig* e=&vpt::rigs[r];
    // Probe from open air, never from the rock behind a wall-mounted nest.
    for(int a=0;a<12;a++)
    {
        float angle=gr()*6.283f;Vec p=home+(Vec){math::cos(angle)*(1+gr()*2),0,math::sin(angle)*(1+gr()*2)};
        p[1]=vpt::ground_at({p[0],0,p[2]},0)+0.65f;
        if(vpt::solid_terrain(p[0],p[1],p[2]))continue;
        Vec dir=a%3==0?(Vec){0,1,0}:(Vec){math::cos(angle+3.14159f),0,math::sin(angle+3.14159f)};
        vpt::Pick h=vpt::world_pick({p,dir});
        if(!h.hit||h.distance>7||h.distance<0.1f||h.normal[1]>0.5f)continue;
        vpt::set_surface(e,h.normal);e.x=h.point[0];e.y=h.point[1];e.z=h.point[2];e.planted=false;
        e.yaw=gr()*6.283f;e.desired_yaw=e.yaw;e.climb_time=0;e.climb_stay=35+gr()*40;return;
    }
}
fn int hatch_brood(vpt::Rig* nest,bool burst)
{
    if(skitter_def<0||vpt::rig_count>=vpt::MAX_RIGS)return -1;
    float a=gr()*6.283f;
    Vec pos=vpt::rig_to_world(nest,{math::cos(a)*0.75f,0.35f,math::sin(a)*0.75f});
    Vec up=nest.oriented?nest.up:(Vec){0,1,0};vpt::Pick surface=vpt::surface_pick(pos,up,0.7f);
    if(surface.hit)pos=surface.point;
    int id=vpt::spawn_rig(skitter_def,pos,a,0.65f+gr()*0.25f,true);if(id<0)return -1;
    classify(id);brood[id].home={nest.x,nest.y,nest.z};aware[id]=burst||brood_alarm_near(pos);brood[id].alarm=aware[id];
    vpt::Rig* baby=&vpt::rigs[id];baby.patrol=true;baby.wait=0;baby.climb_stay=40+gr()*40;
    if(nest.oriented&&surface.hit) { vpt::set_surface(baby,surface.normal);baby.climb_time=0; }
    else if(nest.oriented) { baby.airborne=true;baby.jump_velocity=up*2; }
    if(burst)
    {
        if(baby.oriented) { baby.goal=pos+vpt::rig_dir(baby,{0,0,2}); }
        else { baby.knock={math::cos(a)*4,0,math::sin(a)*4}; }
    }
    flash(pos+up*0.25f,{12,3,18},2,0.15f);audio::play_sound(SND_HATCH,pos,1.8f,jitter(0.1f));stat_hatches++;return id;
}
fn bool brood_alarm_near(Vec p)
{
    for(int n=0;n<vpt::rig_count;n++)if(kind[n]==NEST&&brood[n].alarm)
    { Vec dv=p-(Vec){vpt::rigs[n].x,vpt::rigs[n].y,vpt::rigs[n].z};if(vpt::dot(dv,dv)<225)return true; }
    return false;
}
fn void update_nest(int r,float dt,Vec target,bool active,bool firing=false)
{
    if(!active)return;
    vpt::Rig* e=&vpt::rigs[r];Vec dv=target-(Vec){e.x,e.y,e.z};
    float ds=vpt::dot(dv,dv);
    if(!brood[r].alarm&&(ds<30||(firing&&ds<144))&&gr()<dt*3&&brood_sees(e,target+(Vec){0,0.5f,0}))alarm_brood();
    spawn_cool[r]-=dt;
    if(spawn_cool[r]>0)return;
    int local=0;Vec home={e.x,e.y,e.z};
    for(int s=0;s<vpt::rig_count;s++)if(kind[s]==SKITTER)
    { Vec d=brood[s].home-home;if(vpt::dot(d,d)<1)local++; }
    // Population bounded for performance, but no global ten-skitter cutoff starving every nest.
    if(local>=5||vpt::rig_count>=vpt::MAX_RIGS-7) { spawn_cool[r]=0.75f;return; }
    int baby=hatch_brood(e,false);spawn_cool[r]=baby>=0?(brood[r].alarm?2.0f:4.0f)+gr()*2:1.0f;
}
// Cave-wings are territorial, not colony soldiers. User-provided clicks, death and wing-flap recordings.
fn Vec flutter_home_air(int r)
{
    Vec home=brood[r].home;
    for(int k=0;k<40;k++)
    {
        float a=(float)k*2.399963f;float rad=(float)(k/8)*0.6f;
        Vec p=home+(Vec){math::cos(a)*rad,0.8f,math::sin(a)*rad};
        if(gen_active&&gen_layer== -1)p[1]=1;
        if(vpt::flight_in_bounds(p))return p;
    }
    return home+(Vec){0,0.8f,0};
}
fn bool flutter_roost(int r,Vec p)
{
    Vec dv=p-brood[r].home;dv[1]=0;
    return vpt::flight_in_bounds(p)&&vpt::dot(dv,dv)<=144;
}
fn void flutter_destination(int r,Vec away)
{
    vpt::Rig* e=&vpt::rigs[r];BroodMind* b=&brood[r];Vec pos={e.x,e.y,e.z};
    // Lift once on take-off. Retrying an airborne route must NOT add another 0.8 m every time.
    Vec origin=pos;if(!e.flying)origin+=e.oriented?e.up*0.4f:(Vec){0,0.35f,0};
    if(!vpt::flight_in_bounds(origin))origin=flutter_home_air(r);
    Vec home=flutter_home_air(r);Vec back=home-origin;Vec flat=back;flat[1]=0;
    if(vpt::dot(flat,flat)>64)away=back;
    b.perch=home;b.normal={};
    for(int k=0;k<16;k++)
    {
        Vec dir=k==0?nrm(away+(Vec){0,0.2f,0}):nrm((Vec){gr()*2-1,gr()*1.2f-0.35f,gr()*2-1});
        vpt::Pick h=vpt::world_pick({origin,dir});Vec perch=h.point+h.normal*0.18f;
        if(!h.hit||h.distance<0.6f||h.distance>7||h.normal[1]>0.7f||!flutter_roost(r,perch))continue;
        b.perch=perch;b.normal=h.normal;break;
    }
    if(vpt::dot(b.normal,b.normal)<0.5f)
    {
        vpt::pick_floor=true;vpt::Pick floor=vpt::world_pick({home,{0,-1,0}});vpt::pick_floor=false;
        Vec perch=floor.point+(Vec){0,0.18f,0};
        if(floor.hit&&flutter_roost(r,perch)) { b.perch=perch;b.normal={0,1,0}; }
    }
    if(e.oriented)vpt::detach_surface(e);
    e.x=origin[0];e.y=origin[1];e.z=origin[2];e.flying=true;e.airborne=false;e.flight_blocked=false;e.planted=false;b.flight=0;stat_flights++;
}
fn void update_flutter(int r,float dt,Vec target,bool active,bool firing)
{
    vpt::Rig* e=&vpt::rigs[r];BroodMind* b=&brood[r];e.hunting=false;e.patrol=false;e.climb_time=0;
    if(!active) { e.velocity={};return; }
    if(e.flying&&(!vpt::flight_in_bounds({e.x,e.y,e.z})||e.flight_blocked))
    {
        if(!vpt::flight_in_bounds({e.x,e.y,e.z})) { Vec home=flutter_home_air(r);e.x=home[0];e.y=home[1];e.z=home[2];e.velocity={}; }
        flutter_destination(r,brood[r].home-(Vec){e.x,e.y,e.z});
    }
    b.think-=dt;b.chirp-=dt;Vec pos={e.x,e.y,e.z};Vec dv=target-pos;float ds=vpt::dot(dv,dv);
    if(b.chirp<=0)
    { audio::play_sound(SND_FLUTTER_CLICK+(int)(gr()*2.99f),vpt::rig_to_world(e,{0,0.2f,0}),0.65f,jitter(0.12f));b.chirp=3+gr()*6; }
    if(!aware[r]&&ds<49&&gr()<dt*3&&brood_sees(e,target+(Vec){0,0.5f,0}))
    {
        if(ds<6||(firing&&ds<36)) { b.suspicion+=1;aware[r]=true;b.scatter=1.8f;b.think=0; }
    }
    if(aware[r]&&ds>225&&!b.alarm) { aware[r]=false;b.suspicion=0; }
    b.scatter=math::max(0.0f,b.scatter-dt);
    if(e.flying)
    {
        b.flight+=dt;Vec goal=b.perch;
        bool attack=aware[r]&&b.scatter<=0&&ds<81&&flutter_roost(r,target+(Vec){0,0.4f,0});
        if(attack)goal=target+(Vec){math::sin(e.time*5+(float)r)*0.45f,0.4f,math::cos(e.time*4)*0.45f};
        Vec to=goal-pos;float dist=math::sqrt(vpt::dot(to,to));
        Vec want=nrm(to)*(attack?5.5f:2.8f)+ (Vec){0,math::sin(e.time*13)*0.25f,0};
        e.velocity+=(want-e.velocity)*vpt::clampf(dt*8,0,1);e.yaw=math::atan2(e.velocity[0],e.velocity[2]);
        if(!attack&&(dist<0.28f||b.flight>4))
        {
            if(vpt::dot(b.normal,b.normal)>0.5f&&dist<0.5f)
            {
                e.flying=false;e.velocity={};e.planted=false;b.think=2+gr()*5;
                vpt::set_surface(e,b.normal);Vec p=b.perch-b.normal*0.18f;e.x=p[0];e.y=p[1];e.z=p[2];e.climb_stay=90;
            }
            else { flutter_destination(r,-dv); }   // blocked route: choose another perch, never fall out of the air
        }
        if(attack&&ds<1&&attack_cool[r]<=0)
        {
            robot_hit(nrm(dv),4,0.65f,species_of(r));stat_attacks++;attack_cool[r]=1.4f;b.scatter=1.2f;
            flutter_destination(r,-dv);b.think=2;
            if(player_hp<=0) { player_hp=0;die(); }
        }
        return;
    }
    if(b.think<=0)
    {
        // A little surface scuttle, then a short flight to another perch. Threats first cause escape.
        if(!aware[r]&&e.oriented&&gr()<0.5f)
        {
            e.patrol=true;e.has_goal=true;float a=gr()*6.283f;e.goal=pos+vpt::rig_dir(e,{math::cos(a),0,math::sin(a)})*0.6f;b.think=0.7f;
        }
        else { flutter_destination(r,aware[r]&&b.scatter<=0?dv:-dv);b.think=2+gr()*3; }
    }
    else if(e.oriented&&e.has_goal) { e.patrol=true; }
}
fn ZString vision_class(int creature,bool boss=false) => creature==SCAVENGER?"ash-scavenger":creature==STALKER?(boss?"dune-stalker.elder":"dune-stalker"):creature==FLUTTER?"flutter":creature==SKITTER?"skitter":creature==NEST?"nest":creature==BLOATER?"bloater":creature==CRAWLER?(boss?"crawler.boss":"crawler"):"unknown";
// Surface hops are opportunistic, not long-range homing attacks. Measure the complete 3D gap.
fn bool short_skitter_hop(vpt::Rig* e,Vec target)
{
    Vec gap=target+(Vec){0,0.35f,0}-((Vec){e.x,e.y,e.z}+e.up*0.14f);
    float ds=vpt::dot(gap,gap);return ds>=0.16f&&ds<=4&&math::abs(gap[1])<=1.2f;
}
fn void hop_skitter(int r,Vec target)
{
    vpt::Rig* e=&vpt::rigs[r];if(!short_skitter_hop(e,target))return;
    Vec start=(Vec){e.x,e.y,e.z}+e.up*0.14f;Vec gap=target+(Vec){0,0.35f,0}-start;
    float travel=vpt::clampf(math::sqrt(vpt::dot(gap,gap))/6,0.22f,0.38f);
    vpt::detach_surface(e);e.x=start[0];e.y=start[1];e.z=start[2];e.airborne=true;e.air_time=0;
    e.jump_velocity=gap/travel+(Vec){0,9*travel,0};e.yaw=math::atan2(gap[0],gap[2]);
    attack_cool[r]=0;brood[r].leap=10+gr()*10;stat_leaps++;
    audio::play_sound(SND_SCREECH,start,0.65f,jitter(0.15f)*1.3f);
}
fn bool update_skitter(int r,float dt,Vec target,bool active,bool firing)
{
    vpt::Rig* e=&vpt::rigs[r];BroodMind* b=&brood[r];
    if(!active) { e.hunting=false;e.patrol=false;return true; }
    b.think-=dt;b.leap-=dt;
    Vec pos={e.x,e.y,e.z};Vec dv=target-pos;float ds=vpt::dot(dv,dv);
    if(e.oriented)stat_surface_skitters++;
    // Distant passive sight is harmless. Close approach / nearby firing causes an initial retreat.
    if(!aware[r]&&ds<144&&gr()<dt*4)
    {
        if(brood_sees(e,target+(Vec){0,0.5f,0}))
        {
            bool disturbed=ds<9||(firing&&ds<100);
            b.suspicion=disturbed?b.suspicion+1:math::max(0.0f,b.suspicion-0.2f);
            if(b.suspicion>=1) { aware[r]=true;b.scatter=1.1f+gr()*1.5f;b.think=0; }
        }
        else { b.suspicion=math::max(0.0f,b.suspicion-0.3f); }
    }
    if(aware[r]&&!b.alarm&&ds>144) { aware[r]=false;b.suspicion=0;b.scatter=0; }
    if(!aware[r]||b.scatter>0)
    {
        bool fleeing=b.scatter>0;b.scatter=math::max(0.0f,b.scatter-dt);e.hunting=false;e.speed_mul=fleeing?1.8f:0.65f;
        if(b.think<=0)
        {
            float a=gr()*6.283f;Vec goal;
            if(fleeing) { goal=pos+nrm(pos-target)*3+vpt::rig_dir(e,{math::cos(a),0,math::sin(a)})*0.6f;b.think=0.25f; }
            else
            {
                b.think=1.0f+gr()*3.5f;
                Vec home=b.home;home[1]=pos[1];
                goal=home+(Vec){math::cos(a)*(0.8f+gr()*2),0,math::sin(a)*(0.8f+gr()*2)};
                if(e.oriented) { Vec back=home-pos;back-=e.up*vpt::dot(back,e.up);goal=pos+nrm(back)*0.8f+vpt::rig_dir(e,{math::cos(a)*1.5f,0,math::sin(a)*1.5f}); }
            }
            e.goal=goal;e.has_goal=true;e.burst=1;e.wait=0;
            e.patrol=fleeing||gr()>0.35f;   // pause to tend the nest / cluster between short scuttles
            if(!e.oriented&&vpt::blocked(goal[0],goal[2],e.y,0.15f)) { e.goal=pos+(goal-pos)*0.25f; }
        }
        return true;
    }
    e.patrol=false;e.speed_mul=1.1f;
    if(e.airborne)return false;
    if(e.oriented)
    {
        // Stay on the rock and scuttle, even directly above the player. No automatic ceiling dive.
        e.hunting=false;e.patrol=true;e.speed_mul=0.85f;
        e.climb_stay=math::max(e.climb_stay,e.climb_time+5);
        if(b.think<=0||!e.has_goal)
        {
            Vec along=dv-e.up*vpt::dot(dv,e.up);float a=gr()*6.283f;
            e.goal=pos+nrm(along)*0.7f+vpt::rig_dir(e,{math::cos(a),0,math::sin(a)})*0.9f;
            e.has_goal=true;b.think=0.7f+gr()*1.2f;
        }
        // About one chance per 12.5 eligible seconds, then a 10–20 s cooldown. Never bridge a large drop.
        if(b.leap<=0&&short_skitter_hop(e,target)&&gr()<dt*0.08f&&brood_sees(e,target+(Vec){0,0.5f,0}))hop_skitter(r,target);
        return true;
    }
    return false;
}

// ---------------------------------------------------------------- start / stop
fn void game_start()
{
    player=vpt::controlled_rig;if(!is_player_rig(player))return;player_home=player;
    game_on=true;game_over=false;layer_clear=false;player_hp=100;hurt=0;shake=0;fire_cool=0;blast_count=0;dmg_texts={};hit_texts={};marker_t=0;bar_t={};bar_shown={};vpt::rig_hit_flash={};rocket_charge=0;rocket_voice= -1;popup_t=0;game_time=0;skills_reset();god=false;auto_aim=false;cheat_open=false;cheat_rect={};for(int l=0;l<12;l++)step_phase[l]= -1;
    bolt_count=0;debris_count=0;debris_next=0;flash_count=0;current_room= -1;
    char[256] saved;vpt::copy_text(&saved[0],256,(ZString)&vpt::message[0]);
    cube_asset=vpt::make_cube_asset("debris-cube",1,0xffffff,0);
    bolt_asset=vpt::make_cube_asset("tracer",1,vpt::rgba(255,200,110),7);
    pellet_asset=vpt::make_cube_asset("pellet",1,vpt::rgba(255,160,40),2.2f);   // lower glow: the streak colours stay saturated
    if(pellet_asset>=0)vpt::pinned_assets[pellet_asset]=true;
    gate_asset=vpt::import_asset("assets/library/BLACK_START/bulkhead-door.vpt.json");
    if(gate_asset>=0) { vpt::Asset* g=&vpt::assets[gate_asset];gate_scale=4.2f/math::max(0.5f,(float)math::max(g.dx,g.dz)*g.size); }
    // Nests release skitters: their parts must already be in the atlas so spawning never re-uploads it.
    skitter_def=vpt::load_rig("assets/library/BLACK_START/alien-skitter.rig.json");
    vpt::copy_text(&vpt::message[0],256,(ZString)&saved[0]);
    if(cube_asset>=0)vpt::pinned_assets[cube_asset]=true;if(bolt_asset>=0)vpt::pinned_assets[bolt_asset]=true;if(gate_asset>=0)vpt::pinned_assets[gate_asset]=true;
    if(skitter_def>=0)for(int k=0;k<vpt::rig_defs[skitter_def].part_count;k++)vpt::pinned_assets[vpt::rig_defs[skitter_def].parts[k].asset]=true;
    if(!weapons_load())vpt::report("Weapon attachments missing (<mech>.weapons.json): legacy muzzles.");
    atmosphere_init();
    vpt::copy_text(&vpt::message[0],256,(ZString)&saved[0]);
    vpt::scene_revision++;   // one atlas upload with the pinned assets
    audio_init();audio::play_sound(SND_AMBIENCE,{},0.55f,1,false,true,0);audio::play_sound(SND_MUSIC,{},0.22f,1,false,true,0);
    for(int r=0;r<vpt::rig_count;r++) { classify(r);vpt::rigs[r].patrol=false;vpt::rigs[r].has_goal=false; }
    progression_init();
    stat_hatches=0;stat_brood_bursts=0;stat_leaps=0;stat_surface_skitters=0;stat_flights=0;
    // Colonies start with residents already on the rock, not only floor walkers that might find a wall.
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SKITTER||kind[r]==FLUTTER)
    {
        Vec spawn={vpt::rigs[r].x,vpt::rigs[r].y,vpt::rigs[r].z};
        brood[r].home=kind[r]==FLUTTER?spawn:brood_home(spawn);
        if(vpt::rigs[r].climber&&(kind[r]==FLUTTER||gr()<0.8f))settle_brood(r,brood[r].home);
    }
    for(int i=0;i<vpt::MAX_INSTANCES;i++)prop_hp[i]= -1;
    for(int i=0;i<vpt::MAX_INSTANCES;i++)prop_full[i]=i<vpt::instance_count&&vpt::assets[vpt::instances[i].asset].prop_clone?math::max(1,vpt::assets[vpt::instances[i].asset].occupied):0;
    vpt::carved_count=0;
    for(int k=0;k<MAX_GAME_ROOMS;k++) { room_clear[k]=false;room_locked[k]=false; }
    for(int k=0;k<128;k++)door_open[k]=1;pickup_count=0;shop_init();minimap_reset();
    loot_init();
    for(int k=0;k<game_room_count;k++)if(game_rooms[k].kind==1)room_clear[k]=true;
    vpt::blocking_on=true;vpt::rigs[player].strafe=true;
    vpt::rigs[player].wall_grip=true;vpt::rigs[player].grip_radius=ROBOT_GRIP[robot_of(player)];heavy_t=0;   // the robot squeezes past rock too and braces its feet on it
    saved_tilt=vpt::tilt;saved_zoom=vpt::zoom;vpt::tilt=1.02f;vpt::zoom=game_room_count?9:7;
    if(gen_active&&gen_layer==0) { vpt::report("LAYER 0 / THE ASH WASTE: explore the roofed side caves; defeat the alien crawler in one to awaken the rift. V: view, R: new expedition."); }
    else { vpt::report(game_room_count?"DEPTHS: WASD move, mouse aim, left mouse fire. Big crawlers drop keys for the shop room (E). V: camera, R restarts.":"COMBAT: WASD move, mouse aim, left mouse fire. R restarts, P / Esc quits."); }
}
fn void classify(int r)
{
    surface_gravel_phase[r]=0;brood[r]={};brood[r].home={vpt::rigs[r].x,vpt::rigs[r].y,vpt::rigs[r].z};brood[r].think=gr()*2;brood[r].leap=8+gr()*12;
    brood[r].temperament=0.2f+vpt::hash2((int)vpt::rigs[r].x,(int)vpt::rigs[r].z,vpt::rigs[r].shape_seed)*0.65f;
    brood[r].interest=brood[r].home;
    int def=vpt::rigs[r].def;float s=vpt::rigs[r].scale;kind[r]=NONE;crawl_voice[r]= -1;fuse[r]= -1;rush[r]=0;attack_cool[r]=0.5f+gr();spawn_cool[r]=2+gr()*2;flinch[r]=0;
    if(r==player) { kind[r]=PLAYER;return; }
    if(def_named(def,"scavenger")) { kind[r]=SCAVENGER;hp[r]=3; }
    else if(def_named(def,"dune-stalker")) { kind[r]=STALKER;hp[r]=s>1.3f?75:12;vpt::rigs[r].wall_grip=true;brood[r].leap=1+brood[r].temperament*2; }
    else if(def_named(def,"skitter")) { kind[r]=SKITTER;hp[r]=2;vpt::rigs[r].climber=vpt::terrain_hidden&&gen_active; }   // scuttle over walls and roof too
    else if(def_named(def,"flutter")) { kind[r]=FLUTTER;hp[r]=3;vpt::rigs[r].climber=vpt::terrain_hidden&&gen_active;brood[r].chirp=1+gr()*7;brood[r].think=2+gr()*5; }
    else if(def_named(def,"crawler")) { kind[r]=CRAWLER;hp[r]=s>1.3f?60:16;vpt::rigs[r].wall_grip=true;vpt::rigs[r].climber=vpt::terrain_hidden&&gen_active&&s<=1.3f; }   // climbs walls/ceilings where the cave has a roof
    else if(def_named(def,"bloater")) { kind[r]=BLOATER;hp[r]=3; }
    else if(def_named(def,"nest")) { kind[r]=NEST;hp[r]=def_named(def,"spire")?12:7; }
    hp_max[r]=math::max(hp[r],0.1f);bar_t[r]=0;bar_shown[r]=1;vpt::rig_hit_flash[r]=0;
    vpt::rigs[r].held=false;vpt::rigs[r].hunting=false;aware[r]=false;
}
// Ends the game and restores the scene as it was when play started (toggle_play took the snapshot).
fn void game_stop()
{
    if(!game_on)return;game_on=false;profile_flush();tp_clear_fade();vpt::blocking_on=false;vpt::blocker_count=0;stop_all_sounds();
    vpt::clear_dynamic();(void)vpt::undo_edit();
    for(int r=0;r<vpt::rig_count;r++) { vpt::rigs[r].held=false;vpt::rigs[r].hunting=false;vpt::rigs[r].strafe=false;vpt::rigs[r].knock={}; }
    vpt::tilt=saved_tilt;vpt::zoom=saved_zoom;vpt::report("Game ended; the scene is back to how it was.");
}
// New generated layer (seed 0 = random) and straight into play as the robot.
fn void play_generated(uint seed,bool detailed,int layer=0)
{
    if(game_on)game_stop();vpt::controlled_rig= -1;
    if(!seed)seed=(uint)rl::get_random_value(1,2147483646);
    if(!generate_layer(seed,layer,detailed))return;
    if(layer==0)bestiary_run_started();
    after_generated();   // per target (editor: forget the scene file, reframe; game app: nothing)
    for(int r=0;r<vpt::rig_count;r++)if(is_player_rig(r)) { possess_player(r);return; }
}
// Take control of the robot and start the shooter (the editor's P does the same through toggle_play).
fn void possess_player(int r)
{
    vpt::begin_undo();vpt::controlled_rig=r;
    vpt::focus={vpt::rigs[r].x,vpt::rigs[r].y+0.4f,vpt::rigs[r].z};vpt::zoom=5;
    game_start();
}
fn void game_restart()
{
    if(gen_active) { play_generated(0,true,0);return; }   // roguelike: every run is a new layer
    int p=player_home;game_stop();
    if(p>=0&&p<vpt::rig_count) { vpt::begin_undo();vpt::controlled_rig=p;game_start(); }
}

// ---------------------------------------------------------------- effects
fn void flash(Vec p,Vec color,float range,float life)
{
    if(flash_count==16) { for(int k=1;k<16;k++)flashes[k-1]=flashes[k];flash_count--; }
    flashes[flash_count++]={p,color,range,life,life};
}
// One debris cube flying from p; ring buffer, the oldest piece is recycled when full.
// Landing height for debris: the highest terrain voxel at or below the piece (a few voxel lookups, no
// scene ray cast: a kill spawns ~100 pieces); no terrain = the y=0 plane.
fn float floor_below(Vec p)
{
    int x=(int)math::floor(p[0]);int z=(int)math::floor(p[2]);
    for(int y=(int)math::floor(p[1]);y>=vpt::Y_MIN;y--)if(vpt::solid_terrain((float)x+0.5f,(float)y+0.5f,(float)z+0.5f))return math::min((float)(y+1),p[1]);
    return math::min(0.0f,p[1]);
}
int stat_debris;int stat_kills;int stat_props;int stat_impacts;int stat_attacks;
fn void spawn_debris(Vec p,Vec v,float size,uint color,float glow=0,float life=3)
{
    stat_debris++;
    int k;if(debris_count<MAX_DEBRIS) { k=debris_count++; } else { k=debris_next;debris_next=(debris_next+1)%MAX_DEBRIS; }
    float floor=floor_below(p);
    vpt::Quat q=vpt::qaxis(rand_dir(),gr()*6.28f);
    debris[k]={p,p,v,q,q,rand_dir()*(4+gr()*10),size,color&0xffffff,floor,false,glow,life*(0.8f+gr()*0.4f)};
}
// Bursts the voxels of one placed asset/part instance away from a hit direction. `share` of the asset's
// occupied voxels becomes debris (each piece stands for a cluster, sized to keep the volume).
fn void burst_instance(vpt::Instance it,vpt::Quat q,Vec dir,int pieces,float power,float max_size=0.22f)
{
    vpt::Asset* a=&vpt::assets[it.asset];if(a.occupied<=0||pieces<=0)return;
    float vol=(float)a.occupied*a.size*a.size*a.size*it.scale*it.scale*it.scale;
    float size=vpt::clampf(math::pow(vol/(float)pieces,1.0f/3)*0.9f,math::min(0.03f,max_size),max_size);
    float co=math::cos(it.rotation);float si=math::sin(it.rotation);Vec center={it.x,it.y,it.z};
    int n=a.dx*a.dy*a.dz;
    for(int k=0;k<pieces;k++)
    {
        int cell= -1;for(int tries=0;tries<40;tries++) { int c=(int)(gr()*(float)n);if(c>=n)c=n-1;if(a.data[c]&&!vpt::is_glass(a.data[c])) { cell=c;break; } }
        if(cell<0)continue;
        int x=cell%a.dx;int z=(cell/a.dx)%a.dz;int y=cell/(a.dx*a.dz);
        Vec local=a.origin+(Vec){((float)x+0.5f)*a.size,((float)y+0.5f)*a.size,((float)z+0.5f)*a.size};
        local=vpt::qrot(q,local);Vec w={(co*local[0]+si*local[2])*it.scale+it.x,local[1]*it.scale+it.y,(-si*local[0]+co*local[2])*it.scale+it.z};
        Vec out=nrm(w-center+(Vec){0,0.15f,0});
        Vec v=dir*(power*(0.5f+gr()))+out*(power*0.6f*gr())+rand_dir()*(power*0.35f)+(Vec){0,1.5f+gr()*2.5f,0};
        uint c=a.data[cell];float glow=vpt::is_glow(c)?vpt::glow_strength(c):0;
        spawn_debris(w,v,size*(0.7f+gr()*0.6f),c,glow,25);   // splatter stays a while
    }
}
fn uint sample_color(vpt::Instance it)
{
    vpt::Asset* a=&vpt::assets[it.asset];int n=a.dx*a.dy*a.dz;
    for(int tries=0;tries<60;tries++) { int c=(int)(gr()*(float)n);if(c>=n)c=n-1;if(a.data[c])return a.data[c]; }
    return vpt::rgba(120,120,120);
}
fn Vec brighten(uint c,float k)
{
    rl::RLColor col=vpt::color(c);return {math::pow((float)col[0]/255,2.2f)*k+0.02f,math::pow((float)col[1]/255,2.2f)*k+0.02f,math::pow((float)col[2]/255,2.2f)*k+0.02f};
}
// Splatter a whole rig: every part bursts, then the rig is removed (quick: no atlas re-upload).
fn void kill_rig(int r,Vec dir)
{
    stat_kills++;
    if(kind[r]!=PLAYER&&kind[r]!=NONE) { bestiary_kill(r);int gx=xp_for_kill(r);note_enemy_kill(r,gx);gain_xp(gx); }
    if(kind[r]!=PLAYER&&skill_kill_heal()>0)player_hp=math::min(100.0f,player_hp+skill_kill_heal());
    if(kind[r]==BLOATER&&blast_count<24) { blasts[blast_count++]={{vpt::rigs[r].x,vpt::rigs[r].y+0.5f,vpt::rigs[r].z},0.12f}; }
    if(kind[r]==CRAWLER&&shop_room>=0&&!shop_unlocked)
    {
        // Keys: big creatures carry them. The last crawler always drops one if none has dropped yet.
        bool last=count_kind(CRAWLER)<=1;
        if(gr()<(keys_dropped==0?0.6f:0.3f)||(last&&keys_dropped==0&&keys==0)) { add_pickup(vpt::rigs[r].x+0.4f,vpt::rigs[r].z,KEY_KIND);keys_dropped++; }
    }
    if(is_layer_boss(r)&&game_room_count)unlock_layer_exit();
    if(is_layer_boss(r))add_pickup(vpt::rigs[r].x,vpt::rigs[r].z,0);   // the boss always drops a perk
    int total=0;for(int k=0;k<vpt::rig_part_count;k++)if(vpt::rig_part_owner[k]==r)total+=vpt::assets[vpt::rig_parts[k].asset].occupied;
    int budget=kind[r]==SKITTER?60:kind[r]==NEST?110:kind[r]==PLAYER?150:140;
    for(int k=0;k<vpt::rig_part_count;k++)if(vpt::rig_part_owner[k]==r)
    {
        vpt::Instance it=vpt::rig_parts[k];int n=(int)((float)budget*(float)vpt::assets[it.asset].occupied/(float)math::max(total,1)+0.7f);
        burst_instance(it,vpt::rig_part_q[k],dir,n,kind[r]==PLAYER?5:7);
    }
    vpt::Rig rg=vpt::rigs[r];Vec at={rg.x,rg.y+0.4f*rg.scale,rg.z};
    flash(at,kind[r]==PLAYER?(Vec){60,30,8}:(Vec){30,8,40},8,0.35f);
    if(kind[r]!=PLAYER)
    {
        // Gore: a blood spray thrown along the shot plus a ring of droplets; they land and stay as stains.
        const uint[3] BLOOD={0x1a0a8a,0x100660,0x2a10b0};   // 0xBBGGRR: dark reds
        float s=rg.scale;int drops=kind[r]==SKITTER?35:kind[r]==NEST?50:70;
        for(int k=0;k<drops;k++)
        {
            Vec v=(k%3==0?rand_dir()*(2+gr()*4):dir*(4+gr()*7)+rand_dir()*(1.5f+gr()*2.5f))*math::sqrt(s)+(Vec){0,1.5f+gr()*3,0};
            spawn_debris(at,v,(0.035f+gr()*0.06f)*math::sqrt(s),BLOOD[k%3],0,25);
        }
        flash(at,{60,4,6},6*math::sqrt(s),0.25f);
    }
    if(kind[r]==PLAYER) { audio::play_sound(SND_DEATH,at,4.0f,1,false,false,0); } else if(kind[r]==FLUTTER) { audio::play_sound(SND_FLUTTER_DEATH,at,2.0f,jitter(0.08f),true,false,0); } else if(kind[r]==NEST) { audio::play_sound(SND_NEST,at,2.5f,jitter(0.08f)); } else { if(kind[r]==CRAWLER)audio::play_sound(SND_CRAWLER_ROAR,at,2.5f,jitter(0.05f)*(rg.scale>1.3f?0.8f:1.0f),true,false,0); audio::play_sound(SND_SPLAT,at,kind[r]==CRAWLER?5.0f:3.5f,jitter(0.08f)*(kind[r]==SKITTER?1.35f:rg.scale>1.3f?0.7f:0.95f),true,false,0.01f); }shake=math::max(shake,kind[r]==CRAWLER?0.5f:0.25f);
    // Nests burst open and release their brood.
    if(kind[r]==NEST)
    {
        alarm_brood();
        // Free the nest's slot BEFORE hatching, including when close to the rig limit.
        remove_game_rig(r);
        int babies=5+(int)(gr()*3);
        for(int s=0;s<babies;s++)if(hatch_brood(&rg,true)>=0)stat_brood_bursts++;
        return;
    }
    remove_game_rig(r);
}
// remove_rig swaps the last rig into the slot: mirror that in the per-rig game arrays.
fn void remove_game_rig(int r)
{
    int last=vpt::rig_count-1;
    { int v=crawl_voice[r];if(v>=0&&audio::voices[v].state==1&&audio::voices[v].owner==r+1)audio::voices[v].state=0; }
    crawl_voice[r]=crawl_voice[last];crawl_voice[last]= -1;{ int v=crawl_voice[r];if(v>=0&&audio::voices[v].owner==last+1)audio::voices[v].owner=r+1; }
    fuse[r]=fuse[last];rush[r]=rush[last];aware[r]=aware[last];brood[r]=brood[last];surface_gravel_phase[r]=surface_gravel_phase[last];
    kind[r]=kind[last];hp[r]=hp[last];hp_max[r]=hp_max[last];bar_t[r]=bar_t[last];bar_shown[r]=bar_shown[last];vpt::rig_hit_flash[r]=vpt::rig_hit_flash[last];vpt::rig_hit_flash[last]=0;vpt::rig_cutaway[r]=vpt::rig_cutaway[last];vpt::rig_cutaway[last]=0;
    foreach(&h:hit_texts) { if(h.rig==r) { h.rig= -1; } else if(h.rig==last) { h.rig=r; } }
    attack_cool[r]=attack_cool[last];spawn_cool[r]=spawn_cool[last];flinch[r]=flinch[last];
    if(player==r) { player= -1; } else if(player==last) { player=r; }
    vpt::remove_rig(r,true);
}
// Placed assets: size-based HP; baked cave geometry is carved instead of removed wholesale.
fn bool destructible(int id)
{
    // Placed props and building-kit pieces all break. Only baked cave geometry uses terrain carving.
    return !vpt::assets[vpt::instances[id].asset].generated;
}

// ---------------------------------------------------------------- per frame
// Muzzle of barrel b (0/1) in world space: model offset rotated with the body look, then the rig transform.
fn Vec muzzle(int b)
{
    if(weapons_ready&&player>=0&&player<vpt::rig_count&&vpt::rig_part_count>0)return weapon_muzzle(b);   // the actual weapon's bore
    vpt::Rig* r=&vpt::rigs[player];Vec joint={0,0.62f,0};Vec local={b==0?-0.092f:0.092f,0.564f,0.67f};
    vpt::Quat look=vpt::qmul(vpt::qaxis({0,1,0},r.head_yaw*0.017453293f),vpt::qaxis({1,0,0},-r.head_pitch*0.017453293f));
    Vec p=vpt::qrot(look,local-joint)+joint+(Vec){0,r.body_lift,0};return vpt::rig_to_world(r,p);
}
// One trigger pull: bolts from the next barrel (3 with the spread cell), muzzle flash, sound, recoil.
fn void fire_shot(vpt::Rig* me,Vec target,bool rocket)
{
    int rk=rocket?1:0;
    barrel=(barrel+1)%weapon_muzzles();Vec m=muzzle(barrel);
    if(aim_assist()) { Vec locked;if(auto_target(m,target,&locked,rk?ROCKET_SPEED:45.0f))target=locked; }
    Vec d=nrm(target-m);
    float speed=rk?ROCKET_SPEED:45;float dmg=rk?2.5f*(1+0.5f*(float)(rk-1)):1;float size=rk?0.09f*2.5f*(1+0.2f*(float)(rk-1)):0.09f;
    // multi-gun: every gun fires from its own muzzle toward the same target (converging fire)
    for(int g=0;g<gun_count();g++)
    {
        Vec mg=weapon_muzzle(barrel,g);if(!weapons_ready)mg=m;Vec dg=nrm(target-mg);
        if(bolt_count<MAX_BOLTS)bolts[bolt_count++]={mg,mg,dg*speed,rk?1.6f:0.8f,dmg,size,rk,skill_pierce(),skill_bounces(),false};
        if(g>0)flash(mg+dg*0.15f,rk?(Vec){160,70,20}:(Vec){90,50,14},rk?6:4,rk?0.08f:0.04f);
    }
    flash(m+d*0.15f,rk?(Vec){240,110,30}:(Vec){150,80,24},rk?9:7,rk?0.09f:0.05f);
    if(!rk) { last_shot=(last_shot+1+(int)(gr_servo()*4.99f))%6;audio::play_sound(SND_SHOT+last_shot,m,1.05f,jitter(0.04f),true,false,0); }   // the rocket's sound started with its windup
    bool mortar=rk&&robot_of(player)==1;
    me.knock-=(Vec){d[0],0,d[2]}*(rk?(mortar?8.5f:4.5f):0.6f);shake=math::max(shake,rk?(mortar?0.55f:0.38f):0.08f);weapon_fired(barrel);
    if(mortar) { heavy_t=HEAVY_TIME;me.dyn_pitch+=0.17f;me.body_lift-=0.05f; }   // nose rears up, the hull squats on its legs
}
// Shotgun: one shell = a cone of short-lived pellets from the single barrel. Weak per pellet, deadly up close
// and against swarms. The spread cell triples the pellets. Pellets carry no lights and few effects (performance).
fn void fire_shell(vpt::Rig* me,Vec target)
{
    barrel=(barrel+1)%weapon_muzzles();Vec m=muzzle(barrel);   // double barrel: left, right, left...
    if(aim_assist()) { Vec locked;if(auto_target(m,target,&locked,PELLET_SPEED))target=locked; }
    Vec d=nrm(target-m);
    // one shell (9 pellets) per gun, from each gun's own muzzle
    for(int g=0;g<gun_count();g++)
    {
        Vec mg=weapon_muzzle(barrel,g);if(!weapons_ready)mg=m;Vec dg=nrm(target-mg);
        Vec right=nrm(vpt::cross(dg,{0,1,0}));if(vpt::dot(right,right)<0.5f)right={1,0,0};Vec up=vpt::cross(right,dg);
        for(int i=0;i<9&&bolt_count<MAX_BOLTS;i++)
        {
            float a=gr()*6.2832f;float r=math::sqrt(gr())*0.17f;Vec dir=nrm(dg+right*(math::cos(a)*r)+up*(math::sin(a)*r*0.5f));
            bolts[bolt_count++]={mg,mg,dir*(PELLET_SPEED*(0.94f+gr()*0.12f)),0.16f+gr()*0.04f,0.5f,0.06f,0,skill_pierce(),skill_bounces(),true};
        }
        if(g>0)flash(mg+dg*0.2f,(Vec){160,90,30},6,0.06f);
    }
    flash(m+d*0.2f,(Vec){260,140,50},8,0.07f);
    audio::play_sound(SND_SHOTGUN+take(&last_shotgun_take),m,1.0f,jitter(0.04f),true,false,0);
    me.knock-=(Vec){d[0],0,d[2]}*2.4f;shake=math::max(shake,0.26f);weapon_fired(barrel);
}
fn void game_update(float dt,rl::RLRay aim_ray,bool aiming,bool fire)
{
    if(!game_on)return;
    if(coming_soon) { vpt::control_input={};return; }
    if(portal_fade>0) { progression_update(dt);vpt::control_input={};return; }
    if(player<0||player>=vpt::rig_count||vpt::controlled_rig!=player) { if(!game_over)game_stop();return; }
    game_time+=dt;if(!game_over)bestiary_tick(dt);popup_t=math::max(0.0f,popup_t-dt);foreach(&t:dmg_texts) { if(t.t>0) { t.t-=dt;t.p[1]+=dt*0.9f; } }
    foreach(&t:hit_texts) { if(t.t>0) { t.t-=dt;t.p[1]+=dt*(t.kill?1.4f:0.8f); } }marker_t=math::max(0.0f,marker_t-dt);
    for(int r=0;r<vpt::rig_count;r++) { vpt::rig_hit_flash[r]=math::max(0.0f,vpt::rig_hit_flash[r]-dt*9);bar_t[r]=math::max(0.0f,bar_t[r]-dt);float f=hp_max[r]>0?vpt::clampf(hp[r]/hp_max[r],0,1):0;bar_shown[r]+=(f-bar_shown[r])*math::min(1.0f,dt*5); }hurt=math::max(0.0f,hurt-dt*2.5f);shake=math::max(0.0f,shake-dt*2);fire_cool-=dt;weapon_update(dt);skills_update(dt);
    vpt::Rig* me=&vpt::rigs[player];Vec me_p={me.x,me.y,me.z};
    // ---- aim: the mouse ray's first hit (creatures included, never the robot itself)
    if(aiming&&!game_over)
    {
        vpt::Pick aim=vpt::pick_scene(aim_ray,-1,true,player);
        Vec target=aim.hit?aim.point:aim_ray.position+aim_ray.direction*20;
        if(aim_assist())
        {
            Vec locked;bool valid=auto_target(muzzle((barrel+1)%weapon_muzzles()),target,&locked,weapon==W_ROCKET?ROCKET_SPEED:weapon==W_SHOTGUN?PELLET_SPEED:45.0f);
            if(valid) { target=locked;aim_lock_p=locked;aim_lock_t=0.25f; } else { fire=false; }   // don't waste assisted shots on an occluding wall
        }
        me.has_look_point=true;me.look_point=target;me.strafe_yaw=math::atan2(target[0]-me.x,target[2]-me.z);
        // Rocket launcher: a forced windup (can't be cancelled or spammed). The launch sound's whoosh IS the
        // windup; the rocket leaves at the bang in it. Overclock speeds sound and timing up together.
        float rate_up=skill_rate_mul();
        if(rocket_charge>0)
        {
            rocket_charge-=dt;
            if(rocket_voice>=0&&audio::voices[rocket_voice].state==1&&audio::voices[rocket_voice].sound==SND_ROCKET)audio::voices[rocket_voice].pos=muzzle((barrel+1)%weapon_muzzles());
            if(rocket_charge<=0) { fire_shot(me,target,true);fire_cool=0.45f/rate_up; }
        }
        else if(fire&&fire_cool<=0)
        {
            if(!weapon_ready()) { }
            else if(weapon==W_ROCKET)
            {
                float rate=ROCKET_PITCH*rate_up;rocket_charge=ROCKET_WINDUP/rate;
                rocket_voice=audio::play_sound(SND_ROCKET,muzzle((barrel+1)%weapon_muzzles()),1.0f,rate,true,false,0);
            }
            else if(weapon==W_SHOTGUN) { fire_shell(me,target);fire_cool=0.85f/rate_up; }
            else { fire_shot(me,target,false);fire_cool=math::max(0.03f,0.09f/rate_up); }
        }
    }
    // ---- bolts: swept ray per frame
    for(int b=0;b<bolt_count;)
    {
        Bolt* t=&bolts[b];t.prev=t.p;t.life-=dt;float step=math::sqrt(vpt::dot(t.v,t.v))*dt;Vec d=nrm(t.v);
        vpt::Pick hit=vpt::shot_pick({t.p,d},player);
        if(hit.hit&&hit.distance<=step)
        {
            bool creature=hit.rig>=0&&hit.rig<vpt::rig_count&&kind[hit.rig]!=NONE&&kind[hit.rig]!=PLAYER;
            Bolt bt=*t;
            if(creature)
            {
                hit_rig(hit.rig,hit.point,d,bt.dmg,bt.pellet);if(bt.rocket)explode(hit.point-d*0.2f,bt.rocket);
                if(bt.pierce>0) { t.pierce--;t.p=hit.point+d*0.7f;b++;continue; }   // through the creature
            }
            else
            {
                hit_surface(hit,d,bt.dmg,bt.pellet);
                if(bt.rocket)explode(hit.point+hit.normal*0.2f,bt.rocket);   // every impact detonates, bouncing or not
                if(bt.bounces>0)
                {
                    // Ricochet: mirror off the surface (picked instances report no normal: bounce straight back).
                    Vec n=hit.instance>=0?nrm((Vec){-d[0],0,-d[2]}):hit.normal;
                    audio::play_sound(SND_RICOCHET,hit.point,0.5f,jitter(0.2f),true,false,0.04f);t.v=t.v-n*(2*vpt::dot(t.v,n));t.p=hit.point+n*0.06f;t.bounces--;t.life=math::max(t.life,0.4f);b++;continue;
                }
            }
            bolts[b]=bolts[--bolt_count];continue;
        }
        t.p+=t.v*dt;if(t.life<=0) { if(t.rocket)explode(t.p,t.rocket);   // out of range: air burst
            bolts[b]=bolts[--bolt_count];continue; }
        b++;
    }
    // ---- creatures (kills above may have moved the robot's rig slot)
    if(player<0||player>=vpt::rig_count)return;me=&vpt::rigs[player];me_p={me.x,me.y,me.z};
    shop_update(dt);minimap_update(dt);
    int alive=0;
    for(int r=0;r<vpt::rig_count;r++)
    {
        if(kind[r]==NONE||kind[r]==PLAYER)continue;
        vpt::Rig* e=&vpt::rigs[r];attack_cool[r]-=dt;flinch[r]=math::max(0.0f,flinch[r]-dt);
        bool active=!e.held&&!game_over;if(active)alive++;
        if(active&&!aware[r]&&gen_active&&gen_layer==0&&is_layer_boss(r)&&surface_inside_cave(me_p)!=surface_cave_at(e.x,e.z))
        { e.hunting=false;e.patrol=false;e.has_look_point=true;e.look_point=me_p+(Vec){0,0.5f,0};continue; }   // discover the surface boss under its roof (shots can still provoke it)
        if(kind[r]==SCAVENGER||kind[r]==STALKER) { update_surface_creature(r,dt,me_p,active,fire);if(game_over)return;continue; }
        if(kind[r]==FLUTTER) { update_flutter(r,dt,me_p,active,fire);if(game_over)return;continue; }
        if(kind[r]==NEST) { update_nest(r,dt,me_p,active,fire);continue; }
        if(kind[r]==SKITTER) { if(update_skitter(r,dt,me_p,active,fire))continue; }
        else if(active&&!aware[r])
        {
            // Not noticed the robot yet: wander (nests just sit). Look for it 4x a second.
            Vec dv0=me_p-(Vec){e.x,e.y,e.z};dv0[1]=0;float d0=math::sqrt(vpt::dot(dv0,dv0));
            if(d0<4) { aware[r]=true; }
            else if(d0<22&&gr()<dt*4)
            {
                Vec eye=vpt::rig_to_world(e,{0,0.5f,0});Vec tgt=me_p+(Vec){0,0.6f,0};Vec dv=tgt-eye;float dl=math::sqrt(vpt::dot(dv,dv));
                vpt::Pick h=vpt::world_pick({eye,dv/dl});if(!h.hit||h.distance>dl-0.3f)aware[r]=true;
            }
            if(!aware[r]) { e.hunting=false;e.patrol=kind[r]!=NEST;continue; }
            e.patrol=false;e.has_goal=false;
        }
        Vec to=me_p-(Vec){e.x,e.y,e.z};to[1]=0;float dist=math::sqrt(vpt::dot(to,to));
        float reach=(kind[r]==SKITTER?0.95f:1.6f)*math::max(e.scale,0.8f);
        e.hunting=active&&flinch[r]<=0;e.hunt_target=me_p;e.hunt_stop=reach*0.7f;
        if(kind[r]==CRAWLER&&active)
        {
            // Sees you -> rushes you: a roar, then 1.9x speed while it keeps line of sight (re-checked 4x a second).
            if(gr()<dt*4)
            {
                Vec eye=vpt::rig_to_world(e,{0,0.6f,0});Vec tgt=me_p+(Vec){0,0.6f,0};Vec dv=tgt-eye;float dl=math::sqrt(vpt::dot(dv,dv));
                vpt::Pick h=vpt::world_pick({eye,dv/dl});bool seen=!h.hit||h.distance>dl-0.3f;
                if(seen&&rush[r]<=0)audio::play_sound(SND_CRAWLER_ROAR,eye,2.2f,jitter(0.06f)*(e.scale>1.3f?0.8f:1.05f),true,false,0);
                rush[r]=seen?2.5f:rush[r];
            }
            rush[r]-=dt;e.speed_mul=rush[r]>0?1.9f:1.0f;
        }
        if(kind[r]==BLOATER)
        {
            e.hunt_stop=0.6f;
            if(active&&fuse[r]<0&&dist<1.9f) { fuse[r]=0.75f;audio::play_sound(SND_HATCH,{e.x,e.y+0.5f,e.z},2.0f,0.6f,true,false,0); }   // a wet gurgle: it's going to blow
            if(fuse[r]>=0)
            {
                e.hunting=false;fuse[r]-=dt;e.scale=math::min(e.scale*(1+dt*0.35f),1.35f);   // swells
                if((int)(fuse[r]*12)%2==0)flash({e.x,e.y+0.7f,e.z},{90,8,4},5,0.05f);   // strobing red
                if(fuse[r]<=0) { kill_rig(r,nrm(to));continue; }
            }
            continue;   // no bite: it only explodes
        }
        if(active&&!e.oriented&&math::abs(e.y-me.y)<0.85f&&dist<reach&&attack_cool[r]<=0)
        {
            attack_cool[r]=kind[r]==SKITTER?0.7f:0.8f;stat_attacks++;float dmg=kind[r]==SKITTER?6:e.scale>1.3f?26:18;
            robot_hit(nrm(to),dmg,kind[r]==SKITTER?0.8f:1.3f,species_of(r));if(kind[r]==SKITTER) { audio::play_sound(SND_SCREECH,{e.x,e.y+0.3f,e.z},0.7f,jitter(0.1f)*1.3f); } else if(e.scale>1.3f) { audio::play_sound(SND_CRAWLER_ROAR,{e.x,e.y+0.5f,e.z},2.5f,jitter(0.06f)*0.85f,true,false,0); } else { audio::play_sound(SND_CRAWLER_ATTACK,{e.x,e.y+0.3f,e.z},1.6f,jitter(0.08f),true,false,0); }me.knock+=nrm(to)*(kind[r]==SKITTER?2.5f:5);e.knock-=nrm(to)*2;
            if(player_hp<=0) { player_hp=0;die();return; }
        }
    }
    // ---- bloater blasts (queued by kill_rig; a blast can kill more bloaters: chain reaction)
    for(int b=0;b<blast_count;)
    {
        blasts[b].t-=dt;if(blasts[b].t>0) { b++;continue; }
        Vec p=blasts[b].p;blasts[b]=blasts[--blast_count];
        bloater_blast(p);if(player_hp<=0) { player_hp=0;die();return; }
        if(player<0||player>=vpt::rig_count)return;me=&vpt::rigs[player];me_p={me.x,me.y,me.z};
    }
    // ---- pickups (stack)
    heavy_t=math::max(0.0f,heavy_t-dt);float bog=heavy_t>0?0.2f+0.8f*(1-heavy_t/HEAVY_TIME)*(1-heavy_t/HEAVY_TIME):1;
    me.speed_mul=math::min(2.2f,skill_move_mul())*ROBOT_SPEED[robot_of(player)]*bog;
    for(int k=0;k<pickup_count;k++)if(!pickups[k].taken)
    {
        Pickup it=pickups[k];float dx=it.x-me.x;float dz=it.z-me.z;
        if(dx*dx+dz*dz<1.4f)
        {
            pickups[k].taken=true;
            if(it.kind==KEY_KIND) { keys++;flash({it.x,0.8f,it.z},{120,90,20},8,0.5f);audio::play_sound(SND_PICKUP,{},1.0f,1.25f,false,false,0);popup_title="KEY";popup_info="opens the shop door (E)";popup_color=0x20c0ff;popup_t=POPUP_TIME;continue; }
            audio::play_sound(SND_PICKUP,{it.x,0.8f,it.z},1.0f,1,false,false,0);
            grant_random_perk({it.x,0,it.z});
        }
    }
    progression_update(dt);
}
// Auto aim (cheat): the creature in line of sight closest to where the mouse points (within 9 m of it),
// else the nearest one within 18 m of the robot.
// Aim at an actual voxel on the largest visible posed parts, not an arbitrary height above the feet.
// This handles tilted wall rigs, ceiling nests, tall creatures and airborne insects identically.
fn bool auto_aim_point(int r,Vec from,Vec* point)
{
    int[4] parts;float[4] weights;int count=0;
    for(int k=0;k<vpt::rig_part_count;k++)if(vpt::rig_part_owner[k]==r)
    {
        vpt::Instance it=vpt::rig_parts[k];vpt::Asset* a=&vpt::assets[it.asset];
        float w=(float)a.occupied*a.size*a.size*a.size*it.scale*it.scale*it.scale;
        int at=count;if(at==4) { if(w<=weights[3])continue;at--; } else { count++; }
        while(at>0&&w>weights[at-1]) { parts[at]=parts[at-1];weights[at]=weights[at-1];at--; }
        parts[at]=k;weights[at]=w;
    }
    for(int p=0;p<count;p++)
    {
        int k=parts[p];vpt::Instance it=vpt::rig_parts[k];Vec lo;Vec hi;vpt::instance_bounds_q(it,vpt::rig_part_q[k],&lo,&hi);
        Vec dir=nrm((lo+hi)*0.5f-from);vpt::Pick h={.instance=-1,.rig=-1,.distance=1e10f};
        vpt::pick_asset({from,dir},it,vpt::rig_part_q[k],-1,r,&h);if(!h.hit)continue;
        vpt::Pick visible=vpt::shot_pick({from,dir},player);
        if(!visible.hit||visible.rig!=r)continue;
        // This central ray is proven to cross occupied voxels. Lead the part's centre, not its near skin,
        // so acceleration/turning errors have the whole body thickness as tolerance.
        *point=(lo+hi)*0.5f;return true;
    }
    return false;
}
fn bool auto_target(Vec from,Vec cursor,Vec* out,float speed=45)
{
    float best=1e9f;bool found=false;
    for(int r=0;r<vpt::rig_count;r++)
    {
        if(kind[r]==NONE||kind[r]==PLAYER)continue;vpt::Rig* e=&vpt::rigs[r];
        Vec c=vpt::rig_to_world(e,{0,0.3f,0});Vec dc=c-cursor;dc[1]*=0.35f;Vec dm=c-from;
        float to_cursor=math::sqrt(vpt::dot(dc,dc));float to_me=math::sqrt(vpt::dot(dm,dm));
        if(to_me>18)continue;float score=to_cursor<9?to_cursor:30+to_me;if(score>=best)continue;
        Vec hit;if(!auto_aim_point(r,from,&hit))continue;
        Vec velocity=e.airborne?e.jump_velocity:e.velocity;Vec delta=hit-from;float t=math::sqrt(vpt::dot(delta,delta))/speed;
        // Fixed-point intercept, bounded to the weapon's practical flight time. No invented root height.
        for(int i=0;i<3;i++) { Vec lead=delta+velocity*t;if(e.airborne)lead[1]-=9*t*t;t=math::min(0.8f,math::sqrt(vpt::dot(lead,lead))/speed); }
        Vec aim=hit+velocity*t;
        if(e.airborne)
        {
            aim[1]-=9*t*t;
            float floor=vpt::ground_at({aim[0],e.y,aim[2]},-1000);
            aim[1]=math::max(aim[1],floor+(hit[1]-e.y));
        }
        Vec ray=aim-from;float distance=math::sqrt(vpt::dot(ray,ray));
        if(vpt::dot(velocity,velocity)>0.04f)
        {
            vpt::Pick wall=vpt::world_pick({from,nrm(ray)});
            if(wall.hit&&wall.distance<distance-math::max(0.15f,e.scale*0.3f))continue;
        }
        best=score;*out=aim;found=true;
    }
    return found;
}
fn int first_part(int r) { for(int k=0;k<vpt::rig_part_count;k++)if(vpt::rig_part_owner[k]==r)return k;return 0; }
fn int count_kind(int k) { int n=0;for(int r=0;r<vpt::rig_count;r++)if(kind[r]==k)n++;return n; }
fn void die()
{
    bestiary_death();game_over=true;vpt::rigs[player].strafe=false;Vec d=nrm((Vec){gr()-0.5f,0,gr()-0.5f});
    kill_rig(player,d);vpt::controlled_rig= -1;
    audio::play_sound(SND_GAME_OVER,{},4.0f,1,false,false,0);   // flat: it's the game's verdict, not a sound in the cave
    vpt::report("MH-6 DESTROYED.  R: try again   Esc: back to the editor");
}
float pellet_fx_time= -1;   // pellets share one impact sound/flash per few frames
fn bool pellet_fx() { if(game_time-pellet_fx_time<0.045f)return false;pellet_fx_time=game_time;return true; }
fn void hit_rig(int r,Vec point,Vec d,float dmg,bool pellet=false)
{
    stat_impacts++;if(r<0||r>=vpt::rig_count||kind[r]==NONE||kind[r]==PLAYER)return;
    vpt::Rig* e=&vpt::rigs[r];uint c=sample_color(vpt::rig_parts[first_part(r)]);Vec back=nrm(-d+(Vec){0,0.4f,0});
    for(int k=0;k<(pellet?2:5);k++)spawn_debris(point,back*(2+gr()*3)+rand_dir()*1.5f+d*1.5f,0.035f+gr()*0.03f,c);
    if(!pellet||pellet_fx()) { if(!pellet)flash(point-d*0.2f,brighten(c,40)+(Vec){8,6,12},5,0.12f);audio::play_sound(SND_HIT_FLESH,point,0.6f,jitter(0.12f)*(kind[r]==SKITTER?1.25f:0.9f)); }
    if(kind[r]==NEST)alarm_brood();
    if(kind[r]==SKITTER||kind[r]==FLUTTER||kind[r]==SCAVENGER||kind[r]==STALKER) { brood[r].alarm=true;brood[r].scatter=0;brood[r].think=0; }
    if(kind[r]==SCAVENGER||kind[r]==STALKER) { brood[r].memory=15;Vec src=player>=0&&player<vpt::rig_count?(Vec){vpt::rigs[player].x,vpt::rigs[player].y,vpt::rigs[player].z}:point-d*4;surface_disturb(r,src,true); }
    hp[r]-=dmg;aware[r]=true;flinch[r]=kind[r]==SKITTER?0.12f:0.06f;e.knock+=(Vec){d[0],0,d[2]}*(kind[r]==SKITTER?4.5f:kind[r]==NEST?0:1.6f)*math::min(dmg,2.0f)*(pellet?1.6f:1);e.has_goal=false;note_enemy_hit(r,point,dmg,pellet);
    if(hp[r]<=0)kill_rig(r,d);
}
fn void damage_prop(int id,Vec d,float dmg)
{
    if(id<0||id>=vpt::instance_count||vpt::hidden[id]||!destructible(id))return;vpt::Instance it=vpt::instances[id];
    if(prop_hp[id]<0) { vpt::Asset* a=&vpt::assets[it.asset];prop_hp[id]=vpt::clampf((float)a.occupied*a.size*a.size*a.size*it.scale*it.scale*it.scale*30,2,18); }
    prop_hp[id]-=dmg;
    if(prop_hp[id]<=0) { stat_props++;burst_instance(it,{0,0,0,1},d,100,6);release_crate_loot(id);vpt::hidden[id]=true;vpt::rig_revision++;shake=math::max(shake,0.2f); }
}
// Carved props: pieces with no voxel path to the prop's footing break off and fall as debris; a crate spills
// its loot once breached; when almost nothing stands any more the remains crumble and the prop is gone.
fn void settle_props()
{
    while(vpt::carved_count>0)
    {
        vpt::carved_count--;int id=vpt::carved_props[vpt::carved_count];Vec at=vpt::carved_at[vpt::carved_count];
        if(id<0||id>=vpt::instance_count||vpt::hidden[id])continue;
        vpt::Instance it=vpt::instances[id];vpt::Asset* a=&vpt::assets[it.asset];
        if(prop_full[id]<=0)prop_full[id]=math::max(1,a.occupied);
        Vec[80] pos;uint[80] col;int left;int loose=vpt::detach_loose(id,&pos,&col,80,&left);Vec center={it.x,it.y,it.z};
        if(loose>0)
        {
            int pieces=math::min(loose,loose>400?80:40);float vox=a.size*it.scale;
            float size=vpt::clampf(math::pow((float)loose*vox*vox*vox/(float)pieces,1.0f/3)*0.9f,math::max(vox,0.03f),0.2f);
            for(int k=0;k<pieces;k++)
            {
                Vec out=nrm(pos[k]-at+(Vec){0,0.1f,0});uint c=col[k];
                spawn_debris(pos[k],out*(0.4f+gr()*1.4f)+rand_dir()*0.5f,size*(0.7f+gr()*0.6f),c,vpt::is_glow(c)?vpt::glow_strength(c):0,25);
            }
            float heavy=math::min(1.0f,(float)loose/600);
            audio::play_sound(SND_HIT_ROCK,center,0.4f+heavy*0.8f,0.8f-heavy*0.25f);shake=math::max(shake,0.1f+heavy*0.25f);
            vpt::refresh_asset_voxels(it.asset);
        }
        if((float)left<(float)prop_full[id]*0.8f)release_crate_loot(id);   // breached: the item falls out (once)
        if(left<=math::max(6,prop_full[id]/50))
        {
            if(left>0)burst_instance(it,{0,0,0,1},{0,0,0},math::min(left,12),1.5f);
            release_crate_loot(id);vpt::hidden[id]=true;vpt::rig_revision++;stat_props++;
        }
    }
}
fn void hit_surface(vpt::Pick hit,Vec d,float dmg,bool pellet=false)
{
    // Pellets: fewer chips, no light, a shared impact sound, smaller bites (a shell is many hits at once).
    // a shot cracking into the ground next to a surface creature startles it (and its pack)
    if(gen_layer==0&&player>=0&&player<vpt::rig_count)for(int r=0;r<vpt::rig_count;r++)if((kind[r]==SCAVENGER||kind[r]==STALKER)&&!aware[r])
    { Vec dv=(Vec){vpt::rigs[r].x,vpt::rigs[r].y,vpt::rigs[r].z}-hit.point;if(vpt::dot(dv,dv)<(kind[r]==STALKER?16:9))surface_disturb(r,{vpt::rigs[player].x,vpt::rigs[player].y,vpt::rigs[player].z},false); }
    stat_impacts++;Vec n=hit.normal;Vec back=nrm(n*0.6f-d*0.4f+(Vec){0,0.3f,0});int chips=pellet?2:6;bool fx=!pellet||pellet_fx();float bite=pellet?0.09f:0.14f;
    if(hit.instance>=0&&hit.instance<vpt::instance_count&&!vpt::hidden[hit.instance])
    {
        vpt::Instance it=vpt::instances[hit.instance];uint c=sample_color(it);
        for(int k=0;k<chips;k++)spawn_debris(hit.point,back*(2+gr()*3)+rand_dir()*1.2f,0.03f+gr()*0.03f,c);
        if(vpt::assets[it.asset].generated)
        {
            blast_terrain(hit.point+d*0.05f,bite,0.25f);if(!pellet)flash(hit.point-d*0.2f,{70,36,10},4.5f,0.08f);
            if(fx)audio::play_sound(SND_HIT_ROCK,hit.point,0.45f,jitter(0.15f));return;
        }
        if(!pellet)flash(hit.point-d*0.2f,brighten(c,30)+(Vec){10,8,6},5,0.1f);if(fx)audio::play_sound(SND_HIT_ROCK,hit.point,0.45f,jitter(0.15f)*0.85f);
        // Carvable props lose real voxels (no hit points): settle_props drops whatever lost its footing.
        if(vpt::assets[it.asset].prop_clone) { blast_terrain(hit.point+d*0.04f,pellet?0.1f:0.16f+0.04f*math::min(dmg,2.0f),0.15f,true);return; }
        damage_prop(hit.instance,d,dmg);return;   // props without a private voxel copy (editor scenes, atlas budget)
    }
    // terrain / anything else: rock chips in the surface colour
    uint c=vpt::voxel((int)math::floor(hit.point[0]-n[0]*0.05f),(int)math::floor(hit.point[1]-n[1]*0.05f),(int)math::floor(hit.point[2]-n[2]*0.05f));
    if(!c)c=vpt::rgba(70,64,58);
    for(int k=0;k<chips-1;k++)spawn_debris(hit.point+n*0.03f,back*(1.5f+gr()*2.5f)+rand_dir(),0.03f+gr()*0.03f,c);
    blast_terrain(hit.point,bite,0.25f);   // detailed caves: a small chip / scorch mark
    if(!pellet)flash(hit.point+n*0.25f,{70,36,10},4.5f,0.08f);if(fx)audio::play_sound(SND_HIT_ROCK,hit.point,0.45f,jitter(0.15f));
}
// Rocket blast: splash damage + radial knockback on creatures, props in range take damage, a fireball of
// The robot takes a hit: metal strike, sparks and fine hull chips flying off away from the attacker, a red
// flash + vignette, a camera kick and a floating damage number. strength scales the effects (not the damage).
fn void robot_hit(Vec from_dir,float dmg,float strength,int species= -1)
{
    if(player<0||player>=vpt::rig_count)return;
    vpt::Rig* me=&vpt::rigs[player];Vec at={me.x,me.y+0.45f,me.z};
    if(dash_invulnerable())return;   // dash thrusters: nothing lands during the burst
    if(species>=0)last_hit_species=species;   // bestiary: who killed you
    dmg*=skill_armor_mul();note_robot_hurt();
    if(!god)player_hp-=dmg;hurt=math::min(1.4f,hurt+0.6f+dmg*0.02f);shake=math::max(shake,0.35f+0.25f*strength);
    audio::play_sound(SND_ROBOT_HIT+gr_servo_int(6),at,1.6f*strength,jitter(0.07f)*(strength>1.2f?0.85f:1),true,false,0);
    Vec away=nrm(from_dir*(-1)+(Vec){0,0.6f,0});Vec hitp=at-from_dir*0.35f;
    for(int k=0;k<(int)(8*strength);k++)spawn_debris(hitp,away*(3+gr()*4)+rand_dir()*2,0.012f+gr()*0.012f,0x40c8ff,3.0f,0.35f);   // sparks (0xBBGGRR orange)
    int part=first_part(player);if(part>=0)burst_instance(vpt::rig_parts[part],vpt::rig_part_q[part],away,(int)(10*strength),3,0.035f);
    flash(hitp,{180,90,30},4,0.08f);
    dmg_texts[dmg_text_next]={at+(Vec){(gr()-0.5f)*0.4f,0.5f,(gr()-0.5f)*0.4f},dmg,0.9f};dmg_text_next=(dmg_text_next+1)%10;
}
fn int gr_servo_int(int n) => math::min(n-1,(int)(gr_servo()*(float)n));
// Bloater detonation: a level-3 rocket blast on the creatures around it, plus the robot takes damage with
// distance falloff (it can kill you), a heavy knock, gore, a deeper second boom and a big red flash.
fn void bloater_blast(Vec p)
{
    explode(p,3);blast_terrain(p,1.55f,1.0f);   // the big one: a real crater, gouged walls
    if(player>=0&&player<vpt::rig_count)
    {
        vpt::Rig* me=&vpt::rigs[player];Vec to=(Vec){me.x,me.y+0.4f,me.z}-p;float dist=math::sqrt(vpt::dot(to,to));
        if(dist<BLAST_RADIUS)
        {
            float k=1-dist/BLAST_RADIUS;robot_hit(nrm((Vec){to[0],0,to[2]}),BLAST_DAMAGE*(0.25f+0.75f*k),1.6f,SP_BLOATER);
            me.knock+=nrm((Vec){to[0],0,to[2]})*(12*k);
        }
    }
    const uint[3] GOO={0x1010a0,0x0a0870,0x2020d0};   // 0xBBGGRR: dark reds
    for(int k=0;k<60;k++)spawn_debris(p,rand_dir()*(5+gr()*9)+(Vec){0,4,0},0.04f+gr()*0.08f,GOO[k%3],k%7==0?1.5f:0,25);
    flash(p+(Vec){0,1,0},{400,40,20},16,0.6f);flash(p,{200,90,30},10,0.25f);
    audio::play_sound(SND_BOOM,p,2.6f,0.72f,true,false,0);audio::play_sound(SND_SPLAT,p,3.0f,0.8f,true,false,0);
    shake=math::max(shake,1.2f);
}
// sparks and a big short light. Stacked rockets blow wider.
fn void explode(Vec p,int level)
{
    float radius=2.4f*(1+0.3f*(float)(level-1));float dmg=2.5f*(1+0.5f*(float)(level-1));
    for(int r=vpt::rig_count-1;r>=0;r--)
    {
        if(r>=vpt::rig_count||kind[r]==NONE||kind[r]==PLAYER)continue;vpt::Rig* e=&vpt::rigs[r];
        Vec to=(Vec){e.x,e.y+0.3f,e.z}-p;float dist=math::sqrt(vpt::dot(to,to));if(dist>radius)continue;
        float k=1-dist/radius;e.knock+=nrm((Vec){to[0],0,to[2]})*((kind[r]==NEST?0:30)*(0.35f+0.65f*k));hit_rig(r,(Vec){e.x,e.y+0.3f,e.z},nrm(to),dmg*(0.4f+0.6f*k));
    }
    for(int i=0;i<vpt::instance_count;i++)
    {
        vpt::Instance it=vpt::instances[i];if(vpt::hidden[i])continue;Vec to={it.x-p[0],0,it.z-p[2]};
        if(vpt::dot(to,to)<radius*radius&&!vpt::assets[it.asset].prop_clone)damage_prop(i,nrm(to),3);
    }
    const uint[4] FIRE={0x30c8ff,0x1478ff,0x0a3cdc,0x404040};   // yellow, orange, red, soot (0xBBGGRR)
    for(int k=0;k<34;k++)spawn_debris(p,rand_dir()*(4+gr()*7)+(Vec){0,3,0},0.04f+gr()*0.07f,FIRE[k%4],0,1.2f);
    flash(p,{320,150,40},10*(1+0.2f*(float)(level-1)),0.4f);flash(p+(Vec){0,1.2f,0},{120,40,10},14,0.7f);
    blast_terrain(p,0.45f+0.25f*(float)level,0.85f);   // rocket ~0.7 m crater, stacked rockets wider
    blast_terrain(p,radius*0.55f,0.6f,true);   // props inside the blast lose a big bite of voxels
    shake=math::max(shake,0.7f);audio::play_sound(SND_BOOM,p,2.2f,jitter(0.08f),true,false,0.01f);
}

// ---------------------------------------------------------------- rooms
fn int room_at(float x,float z)
{
    for(int k=0;k<game_room_count;k++) { GameRoomFile g=game_rooms[k];if(x>=g.x0&&x<=g.x1&&z>=g.z0&&z<=g.z1)return k; }
    return -1;
}
fn void lock_room(int k)
{
    if(room_locked[k]||room_clear[k])return;room_locked[k]=true;
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER&&room_at(vpt::rigs[r].x,vpt::rigs[r].z)==k)vpt::rigs[r].held=false;
    if(game_rooms[k].kind==3)vpt::report("Something big is in here...");
}
fn void rooms_update(float dt)
{
    if(!game_room_count)return;
    vpt::Rig* me=&vpt::rigs[player];int here=room_at(me.x,me.z);
    // Enter a room (fully inside, past the doorway): lock it if it still has creatures.
    if(here>=0&&here!=current_room)
    {
        GameRoomFile g=game_rooms[here];bool inside=me.x>g.x0+3&&me.x<g.x1-3&&me.z>g.z0+3&&me.z<g.z1-3;   // well past the gate (gates sit on the room edge)
        if(inside) { current_room=here;if(!room_clear[here]&&creatures_in(here)>0) { lock_room(here); } else { room_clear[here]=true; } }
    }
    for(int k=0;k<game_room_count;k++)if(room_locked[k]&&creatures_in(k)==0)
    {
        room_locked[k]=false;room_clear[k]=true;
        if(game_rooms[k].kind==3) { unlock_layer_exit(); }
        else
        {
            vpt::report("Room cleared.");GameRoomFile g=game_rooms[k];
            if(!(gen_active&&gen_layer==0)&&gr()<0.08f) { add_pickup((g.x0+g.x1)*0.5f,(g.z0+g.z1)*0.5f,0);vpt::report("Room cleared. Something dropped..."); }
        }
    }
    // Doors close while either neighbour is locked; they sink into the floor when open.
    vpt::blocker_count=0;
    for(int k=0;k<game_door_count;k++)
    {
        GameDoorFile dr=game_doors[k];bool shut=room_locked[dr.a]||room_locked[dr.b];
        float before=door_open[k];door_open[k]=vpt::clampf(door_open[k]+(shut?-1.0f:1.0f)*dt*3.5f,0,1);
        if((before==1&&door_open[k]<1)||(before==0&&door_open[k]>0))audio::play_sound(SND_DOOR,{dr.x,1,dr.z},1.0f,jitter(0.05f),true,false,0);
        if(door_open[k]<0.6f&&vpt::blocker_count<32) { vpt::blockers[vpt::blocker_count++]=dr.axis==0?(vpt::Blocker){dr.x-0.4f,dr.z-2.2f,dr.x+0.4f,dr.z+2.2f}:(vpt::Blocker){dr.x-2.2f,dr.z-0.4f,dr.x+2.2f,dr.z+0.4f}; }
    }
}
fn int creatures_in(int k)
{
    int n=0;for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER&&room_at(vpt::rigs[r].x,vpt::rigs[r].z)==k)n++;return n;
}

// ---------------------------------------------------------------- physics + GPU objects (after update_rigs)
// Crawling loops: the nearest moving creatures (2 crawlers, 4 skitters) each get a looping walk/crawl
// voice that follows them; loudness and pitch track their speed. Others stay silent so swarms don't mush.
fn void creature_sounds()
{
    if(!audio::ready)return;
    bool[vpt::MAX_RIGS] want;int crawlers=0;int skitters=0;
    for(int pass=0;pass<7;pass++)
    {
        int best= -1;float bd=30*30;
        for(int r=0;r<vpt::rig_count;r++)
        {
            if(want[r]||(kind[r]!=SKITTER&&kind[r]!=CRAWLER&&kind[r]!=BLOATER&&kind[r]!=FLUTTER&&kind[r]!=SCAVENGER&&kind[r]!=STALKER))continue;
            if((kind[r]!=CRAWLER&&skitters>=5)||(kind[r]==CRAWLER&&crawlers>=2))continue;
            vpt::Rig* e=&vpt::rigs[r];if(e.held)continue;
            if(kind[r]==FLUTTER&&!e.flying)continue;
            float sp=math::sqrt(vpt::dot(e.velocity,e.velocity));if(sp<0.35f*e.scale)continue;
            Vec d=(Vec){e.x,e.y,e.z}-audio::listen_pos;float dd=vpt::dot(d,d);if(dd<bd) { bd=dd;best=r; }
        }
        if(best<0)break;
        want[best]=true;if(kind[best]!=CRAWLER) { skitters++; } else { crawlers++; }
    }
    for(int r=0;r<vpt::rig_count;r++)
    {
        int v=crawl_voice[r];bool owned=v>=0&&audio::voices[v].state==1&&audio::voices[v].owner==r+1;
        if(!owned)crawl_voice[r]= -1;
        if(!want[r])
        {
            if(owned) { if(audio::voices[v].gain<=0) { audio::voices[v].state=0;crawl_voice[r]= -1; } else { audio::voices[v].gain=0; } }   // fade, then free
            continue;
        }
        vpt::Rig* e=&vpt::rigs[r];Vec pos={e.x,e.y+0.2f*e.scale,e.z};
        float sp=math::sqrt(e.velocity[0]*e.velocity[0]+e.velocity[2]*e.velocity[2]);
        float gain;float pitch;int k;
        if(kind[r]==CRAWLER||kind[r]==STALKER) { float d=vpt::clampf(sp/(3.4f*e.scale),0.3f,1);gain=2.2f*d;pitch=(e.scale>1.3f?0.8f:1.0f)*(0.9f+0.2f*d);k=SND_CRAWLER_WALK; }
        else if(kind[r]==FLUTTER) { gain=0.8f;pitch=1.3f;k=SND_FLUTTER_FLAP; }
        else if(kind[r]==BLOATER) { float d=vpt::clampf(sp/1.1f,0.3f,1);gain=1.8f*d;pitch=0.62f;k=SND_SKITTER_CRAWL+r%3; }
        else { float d=vpt::clampf(sp/2.6f,0.3f,1);gain=1.5f*d;pitch=(0.95f+0.15f*d)/math::max(e.scale,0.7f);k=SND_SKITTER_CRAWL+r%3; }
        if(!owned)
        {
            v=audio::play_sound(k,pos,gain,pitch,true,true,0);
            if(v>=0) { audio::voices[v].owner=r+1;audio::voices[v].cursor=gr_servo()*(float)math::max(audio::bank[k].length-2,0);crawl_voice[r]=v; }   // random start: no two in sync
        }
        else { audio::voices[v].pos=pos;audio::voices[v].gain=gain;audio::voices[v].rate=pitch; }
    }
}
fn void game_post(float dt)
{
    if(!third_person)tp_clear_fade();
    if(!game_on)return;
    settle_props();
    if(player>=0&&player<vpt::rig_count)robot_servos(&vpt::rigs[player],dt,!game_over);
    creature_sounds();environment_audio_update(dt);
    if(player>=0&&player<vpt::rig_count&&!game_over)
    {
        // A leg finishing its swing = a foot landing: a metal clink right at that foot (casing takes, never the same twice in a row).
        vpt::Rig* me=&vpt::rigs[player];int legs=vpt::rig_defs[me.def].leg_count;
        for(int l=0;l<legs&&l<12;l++)
        {
            if(step_phase[l]>=0&&me.phase[l]<0) { last_foot=(last_foot+1+(int)(gr_servo()*6.99f))%8;audio::play_sound(SND_FOOT+last_foot,me.foot[l],0.19f,0.78f*jitter(0.07f),true,false,0);gravel_contact(me.foot[l]); }
            step_phase[l]=me.phase[l]>=0?1:-1;
        }
    }
    vpt::dyn_begin();vpt::game_light_count=0;
    progression_draw();   // reserve space for the rift before filling the debris budget
    weapons_draw();skills_draw_robot();atmosphere_draw(dt);
    // debris: gravity, bounce, tumble, rock walls; settled pieces stay as splatter
    // Keep any 4 m acceleration cell well under its 128-object limit: the oldest pieces in a crowded cell fade.
    int[vpt::MAX_OBJECT_GRID*vpt::MAX_OBJECT_GRID/16] crowd;int og=vpt::object_grid();
    for(int k=0;k<debris_count;k++)
    {
        Debris* p=&debris[k];p.life-=dt;
        int cx=vpt::clampi((int)((p.p[0]+(float)vpt::world_size*0.5f)/vpt::OBJECT_CELL),0,og-1);int cz=vpt::clampi((int)((p.p[2]+(float)vpt::world_size*0.5f)/vpt::OBJECT_CELL),0,og-1);
        int cell=(cz*og+cx)%(vpt::MAX_OBJECT_GRID*vpt::MAX_OBJECT_GRID/16);if(++crowd[cell]>70&&p.life>0.6f)p.life=0.6f;
    }
    for(int k=0;k<debris_count;)
    {
        if(debris[k].life<=0) { debris[k]=debris[--debris_count];if(debris_next>=debris_count)debris_next=0;continue; }
        k++;
    }
    for(int k=0;k<debris_count;k++)
    {
        Debris* p=&debris[k];p.prev=p.p;p.prev_q=p.q;
        if(!p.rest)
        {
            p.v[1]-=14*dt;Vec next=p.p+p.v*dt;
            if(vpt::solid_terrain(next[0],next[1],p.p[2])&&next[1]>p.floor+0.05f) { p.v[0]*= -0.35f;next[0]=p.p[0]; }
            if(vpt::solid_terrain(p.p[0],next[1],next[2])&&next[1]>p.floor+0.05f) { p.v[2]*= -0.35f;next[2]=p.p[2]; }
            p.p=next;
            float speed=math::sqrt(vpt::dot(p.spin,p.spin));if(speed>0.01f)p.q=vpt::qmul(vpt::qaxis(p.spin/speed,speed*dt),p.q);
            if(p.p[1]-p.size*0.5f<=p.floor)
            {
                p.p[1]=p.floor+p.size*0.5f;
                if(math::abs(p.v[1])<1.6f) { p.rest=true;p.v={};p.q=vpt::qaxis({0,1,0},gr()*6.28f); }
                else { p.v[1]*= -0.3f;p.v[0]*=0.55f;p.v[2]*=0.55f;p.spin*=0.5f; }
            }
        }
        float size=p.size*math::min(1.0f,p.life/0.6f);
        int id=vpt::dyn_add({cube_asset,p.p[0],p.p[1]-size*0.5f,p.p[2],0,size,0},p.q,p.color,true);
        vpt::dyn_set_prev(id,{cube_asset,p.prev[0],p.prev[1]-size*0.5f,p.prev[2],0,size,0},p.prev_q);
    }
    // bolts: a hot core with a short trail, each a moving light
    // Bolts: MG tracers (3 glowing cubes + a light), rockets (the voxel round, rolling, exhaust flame + a light),
    // shotgun pellets (hot white-gold -> orange -> crimson streaks stretched along their speed; one light per shell).
    Vec pellet_sum={};int pellets_alive=0;
    for(int b=0;b<bolt_count;b++)
    {
        Bolt t=bolts[b];Vec d=nrm(t.v);vpt::Quat q=vpt::qaxis({0,1,0},math::atan2(d[0],d[2]));float k=t.size/0.09f;
        if(t.rocket&&rocket_round_asset>=0)
        {
            vpt::Quat rq=vpt::qmul(vpt::qmul(vpt::qaxis({0,1,0},math::atan2(d[0],d[2])),vpt::qaxis({1,0,0},-math::asin(vpt::clampf(d[1],-1,1)))),vpt::qaxis({0,0,1},(1.6f-t.life)*14));
            vpt::Asset* ra=&vpt::assets[rocket_round_asset];Vec c=vpt::qrot(rq,(Vec){0,(float)ra.dy*ra.size*0.5f,0});
            Vec p0=t.p-c;Vec pp=p0-t.v*dt;
            int id=vpt::dyn_add({rocket_round_asset,p0[0],p0[1],p0[2],0,1,0},rq);vpt::dyn_set_prev(id,{rocket_round_asset,pp[0],pp[1],pp[2],0,1,0},rq);
            vpt::game_light(t.p-d*0.3f,(Vec){52,26,7}*2.2f,9,vpt::instance_count+vpt::rig_part_count+id+1);
            const uint[2] FLAME={0x50d2ff,0x1e78ff};   // 0xBBGGRR: yellow core, orange tongue
            for(int s=0;s<2;s++)
            {
                float fl=0.05f-(float)s*0.015f+gr()*0.012f;Vec fp=t.p-d*(0.22f+(float)s*0.08f);
                int fid=vpt::dyn_add({bolt_asset,fp[0],fp[1]-fl*0.5f,fp[2],0,fl,0},q,FLAME[s],true);vpt::dyn_set_prev(fid,{bolt_asset,fp[0]-t.v[0]*dt,fp[1]-fl*0.5f-t.v[1]*dt,fp[2]-t.v[2]*dt,0,fl,0},q);
            }
            continue;
        }
        if(t.pellet)
        {
            const uint[3] HOT={0x9cf6ff,0x1aa0ff,0x4018e8};   // 0xBBGGRR: white-gold head, hot orange, crimson tail
            for(int s=0;s<3;s++)
            {
                Vec p=t.p-d*((float)s*0.15f);float size=0.06f-(float)s*0.012f;
                int id=vpt::dyn_add({pellet_asset,p[0],p[1]-size*0.5f,p[2],0,size,0},q,HOT[s],true);
                vpt::dyn_set_prev(id,{pellet_asset,p[0]-t.v[0]*dt,p[1]-size*0.5f-t.v[1]*dt,p[2]-t.v[2]*dt,0,size,0},q);
            }
            pellet_sum+=t.p;pellets_alive++;continue;
        }
        for(int s=0;s<3;s++)
        {
            Vec p=t.p-d*((float)s*0.11f*k);float size=(0.09f-(float)s*0.02f)*k;
            const uint[3] TRACER={0xa0e6ff,0x3296ff,0x1446dc};   // yellow-white head, orange, red tail (0xBBGGRR)
            int id=vpt::dyn_add({bolt_asset,p[0],p[1]-size*0.5f,p[2],0,size,0},q,TRACER[s],true);
            if(s==0)vpt::game_light(t.p,(Vec){52,26,7},6,vpt::instance_count+vpt::rig_part_count+id+1);
            vpt::dyn_set_prev(id,{bolt_asset,p[0]-t.v[0]*dt,p[1]-size*0.5f-t.v[1]*dt,p[2]-t.v[2]*dt,0,size,0},q);
        }
    }
    if(pellets_alive>0)vpt::game_light(pellet_sum/(float)pellets_alive,(Vec){80,38,10},5);   // the whole shell cloud glows as one
    shop_draw();
    // treasure pickups: a glowing shard turning above the floor
    for(int k=0;k<pickup_count;k++)if(!pickups[k].taken)
    {
        Pickup it=pickups[k];float bob=0.75f+math::sin(game_time*2.4f+(float)k)*0.12f;
        vpt::Quat q=vpt::qmul(vpt::qaxis({0,1,0},game_time*1.7f),vpt::qaxis({1,0,1},0.7f));
        uint col=it.kind==KEY_KIND?0x20c0ff:PERK_COLOR;float ksize=it.kind==KEY_KIND?0.16f:0.22f;   // keys: small gold
        int id=vpt::dyn_add({bolt_asset,it.x,bob,it.z,0,ksize,0},q,col,true);vpt::dyn_set_prev(id,{bolt_asset,it.x,bob,it.z,0,ksize,0},q);
        vpt::game_light({it.x,bob+0.3f,it.z},brighten(col,14),5,vpt::instance_count+vpt::rig_part_count+id+1);
    }
    // Third-person view under the cave roof: a soft warm lantern over the robot (the roof shuts out the sky fill)
    if(tp_active()&&player>=0&&player<vpt::rig_count) { vpt::Rig* me=&vpt::rigs[player];vpt::game_light({me.x,me.y+2.2f,me.z},{7,6,5},9); }
    for(int f=0;f<flash_count;)
    {
        Flash* l=&flashes[f];l.life-=dt;if(l.life<=0) { flashes[f]=flashes[--flash_count];continue; }
        float k=l.life/l.total;vpt::game_light(l.p,l.color*(k*k),l.range);f++;
    }
    vpt::dyn_end();
}
// Camera shake offset for the follow camera.
fn Vec shake_offset() => shake>0?(Vec){(gr()-0.5f)*shake*0.5f,(gr()-0.5f)*shake*0.3f,(gr()-0.5f)*shake*0.5f}:(Vec){0,0,0};
// ---------------------------------------------------------------- vision system (YOLO-style boxes)
bool[vpt::MAX_RIGS] seen;
int vision_frame;
fn float hash01(int a,int b) { uint h=(uint)a*374761393u+(uint)b*668265263u;h=(h^(h>>13))*1274126177u;return (float)((h^(h>>16))&0xffff)/65535.0f; }
fn void draw_vision(rl::RLCamera3D cam,rl::RLRectangle view)
{
    vision_frame++;int shown=0;
    for(int r=0;r<vpt::rig_count;r++)
    {
        if(kind[r]==NONE||kind[r]==PLAYER)continue;vpt::Rig e=vpt::rigs[r];
        // line of sight from the camera, refreshed every 4th frame
        if(vision_frame%4==r%4)
        {
            Vec c={e.x,e.y+0.3f*e.scale,e.z};Vec d=c-cam.position;float dist=math::sqrt(vpt::dot(d,d));
            vpt::Pick h=vpt::pick_scene({cam.position,d/dist},-1,true,-1);seen[r]=!h.hit||h.rig==r||h.distance>dist-0.4f;
        }
        if(!seen[r])continue;
        float x0=1e9f;float y0=1e9f;float x1=-1e9f;float y1=-1e9f;bool front=false;
        for(int k=0;k<vpt::rig_part_count;k++)if(vpt::rig_part_owner[k]==r)
        {
            Vec lo;Vec hi;vpt::instance_bounds_q(vpt::rig_parts[k],vpt::rig_part_q[k],&lo,&hi);
            for(int i=0;i<8;i++)
            {
                Vec w={(i&1)?hi[0]:lo[0],(i&2)?hi[1]:lo[1],(i&4)?hi[2]:lo[2]};if(vpt::dot(w-cam.position,cam.target-cam.position)<=0)continue;front=true;
                rl::RLVector2 sp=rl::get_world_to_screen_ex(w,cam,(int)view.width,(int)view.height)+(rl::RLVector2){view.x,view.y};
                x0=math::min(x0,sp[0]);y0=math::min(y0,sp[1]);x1=math::max(x1,sp[0]);y1=math::max(y1,sp[1]);
            }
        }
        if(!front||x1<view.x||x0>view.x+view.width||y1<view.y||y0>view.y+view.height)continue;
        // detector jitter: the box breathes, slides, re-fits in jumps and drops out for a frame now and then
        float t=game_time;float seed=(float)r*7.31f+(float)kind[r];int tick=(int)(t*9);
        if(hash01(tick,r)<0.04f)continue;
        float w=x1-x0;float h=y1-y0;float cx=(x0+x1)*0.5f+math::sin(t*17+seed)*w*0.025f+(hash01(tick,r+99)-0.5f)*w*0.06f;float cy=(y0+y1)*0.5f+math::cos(t*13+seed)*h*0.025f;
        float jump=1+(hash01(tick/3,r+7)-0.5f)*0.18f;
        w*=(1.08f+0.06f*math::sin(t*11+seed)+0.04f*math::sin(t*23.7f+seed*2))*jump;h*=(1.08f+0.06f*math::cos(t*9.3f+seed)+0.04f*math::sin(t*19.1f+seed))*jump;
        x0=cx-w*0.5f;x1=cx+w*0.5f;y0=cy-h*0.5f;y1=cy+h*0.5f;
        bool boss=is_layer_boss(r);
        rl::RLColor col=kind[r]==SKITTER?ui::ACCENT:kind[r]==NEST?(rl::RLColor){211,134,155,255}:boss?ui::BAD:ui::SELECT;
        ZString cls=vision_class(kind[r],boss);
        float conf=0.58f+0.38f*(0.5f+0.5f*math::sin(t*3.1f+seed))*(0.85f+0.15f*hash01(tick,r+3));
        rl::draw_rectangle_lines_ex({x0,y0,w,h},1,{col.r,col.g,col.b,70});
        float lx=math::min(w,h)*0.28f;
        rl::draw_line_ex({x0,y0},{x0+lx,y0},2,col);rl::draw_line_ex({x0,y0},{x0,y0+lx},2,col);rl::draw_line_ex({x1,y0},{x1-lx,y0},2,col);rl::draw_line_ex({x1,y0},{x1,y0+lx},2,col);
        rl::draw_line_ex({x0,y1},{x0+lx,y1},2,col);rl::draw_line_ex({x0,y1},{x0,y1-lx},2,col);rl::draw_line_ex({x1,y1},{x1-lx,y1},2,col);rl::draw_line_ex({x1,y1},{x1,y1-lx},2,col);
        ZString label=rl::text_format("%s %.2f  #%d",cls,conf,r);int tw=ui::text_width(label,12)+8;
        rl::draw_rectangle((int)x0,(int)y0-17,tw,16,{col.r,col.g,col.b,210});ui::text(label,(int)x0+4,(int)y0-14,12,{29,32,33,255});
        shown++;
    }
    ui::text(rl::text_format("VISION  %d detections  %.0f ms",shown,4+hash01(vision_frame/6,1)*3),(int)view.x+(int)view.width-230,(int)view.y+64,13,{142,192,124,255});
}
// ---------------------------------------------------------------- cheat menu (F2)
// F2: only a layer jump and skill points (the rest of the old cheat list is gone).
fn void draw_cheats(rl::RLRectangle view)
{
    int w=300;int h=172;int x=(int)(view.x+view.width)-w-16;int y=(int)view.y+96;cheat_rect={(float)x,(float)y,(float)w,(float)h};
    rl::draw_rectangle_rounded({(float)x,(float)y,(float)w,(float)h},0.05f,6,{40,40,40,240});rl::draw_rectangle_rounded_lines_ex({(float)x,(float)y,(float)w,(float)h},0.05f,6,1,ui::BG2);
    ui::text("CHEATS",x+16,y+14,18,ui::ACCENT);ui::text("F2 closes",x+w-84,y+18,12,ui::MUTED);
    ui::text("go to layer",x+16,y+50,13,ui::MUTED);
    if(ui::button("0  surface",x+16,y+70,128))cheat_layer=0;
    if(ui::button("-1  caves",x+156,y+70,128))cheat_layer= -1;
    ui::text("skill points",x+16,y+112,13,ui::MUTED);
    if(ui::button("+1",x+16,y+132,128))skill_points++;
    if(ui::button("+5",x+156,y+132,128))skill_points+=5;
}
// Creature health bars (after a hit), merged damage numbers and the hit marker.
fn void enemy_feedback_hud(rl::RLRectangle view,rl::RLCamera3D cam)
{
    Vec fwd=nrm(cam.target-cam.position);
    for(int r=0;r<vpt::rig_count;r++)
    {
        if(bar_t[r]<=0||kind[r]==NONE||kind[r]==PLAYER||hp_max[r]<=0)continue;
        Vec top=rig_top(r)+(Vec){0,0.15f,0};if(vpt::dot(top-cam.position,fwd)<0.3f)continue;
        rl::RLVector2 sp=rl::get_world_to_screen_ex(top,cam,(int)view.width,(int)view.height);
        float a=math::min(1.0f,bar_t[r]/0.4f);float big=hp_max[r]>=30?1.6f:hp_max[r]>=10?1.25f:1;
        int w=(int)(44*big);int h=5;int x=(int)(view.x+sp[0])-w/2;int y=(int)(view.y+sp[1]);
        float f=hp_max[r]>0?vpt::clampf(hp[r]/hp_max[r],0,1):0;
        rl::draw_rectangle(x-1,y-1,w+2,h+2,{12,12,14,(char)(200*a)});
        rl::draw_rectangle(x,y,(int)((float)w*bar_shown[r]),h,{255,236,200,(char)(230*a)});   // the chunk just lost, draining
        rl::RLColor c=f>0.5f?(rl::RLColor){120,230,90,255}:f>0.25f?(rl::RLColor){250,200,60,255}:(rl::RLColor){250,70,50,255};c[3]=(char)(255*a);
        rl::draw_rectangle(x,y,(int)((float)w*f),h,c);
    }
    foreach(t:hit_texts)if(t.t>0)
    {
        if(vpt::dot(t.p-cam.position,fwd)<0.3f)continue;
        rl::RLVector2 sp=rl::get_world_to_screen_ex(t.p,cam,(int)view.width,(int)view.height);float a=math::min(1.0f,t.t/0.3f);
        float age=(t.kill?1.1f:0.9f)-t.t;float pop=1+0.35f*math::max(0.0f,1-age/0.12f);
        ZString s=t.kill?(t.v>0?rl::text_format("%d  KILL",(int)math::ceil(t.v)):(ZString)"KILL"):t.v<10&&t.v-math::floor(t.v)>0.05f?rl::text_format("%.1f",t.v):rl::text_format("%d",(int)(t.v+0.5f));
        int fs=(int)((16+math::min(t.v,12.0f)*0.8f)*pop*(t.kill?1.2f:1));int tx=(int)(view.x+sp[0])-ui::text_width(s,fs)/2;int ty=(int)(view.y+sp[1]);
        rl::RLColor c=t.kill?(rl::RLColor){255,90,60,255}:(rl::RLColor){255,226,120,255};c[3]=(char)(255*a);
        ui::text(s,tx+2,ty+2,fs,{0,0,0,(char)(200*a)});ui::text(s,tx,ty,fs,c);
        if(t.kill&&t.xp>0) { ZString xs=rl::text_format("+%d XP",t.xp);int xw=ui::text_width(xs,14);ui::text(xs,(int)(view.x+sp[0])-xw/2+1,ty+fs+3,14,{0,0,0,(char)(180*a)});ui::text(xs,(int)(view.x+sp[0])-xw/2,ty+fs+2,14,{250,189,47,(char)(255*a)}); }
    }
    if(marker_t>0)
    {
        // An X around the crosshair (third person) or around the hit point (top-down).
        float a=math::min(1.0f,marker_t/0.12f);int cx;int cy;
        if(tp_active()) { cx=(int)(view.x+view.width/2);cy=(int)(view.y+view.height/2); }
        else { rl::RLVector2 sp=rl::get_world_to_screen_ex(marker_p,cam,(int)view.width,(int)view.height);cx=(int)(view.x+sp[0]);cy=(int)(view.y+sp[1]); }
        float r0=marker_kill?9:6;float r1=marker_kill?20:13;float th=marker_kill?3:2;
        rl::RLColor c=marker_kill?(rl::RLColor){255,80,60,255}:(rl::RLColor){255,255,255,255};c[3]=(char)(255*a);
        for(int k=0;k<4;k++)
        {
            float sx=k&1?1:-1;float sy=k&2?1:-1;
            rl::draw_line_ex({(float)cx+sx*r0,(float)cy+sy*r0},{(float)cx+sx*r1,(float)cy+sy*r1},th+1.5f,{0,0,0,(char)(150*a)});
            rl::draw_line_ex({(float)cx+sx*r0,(float)cy+sy*r0},{(float)cx+sx*r1,(float)cy+sy*r1},th,c);
        }
    }
}
fn void draw_game_hud(rl::RLRectangle view,rl::RLCamera3D cam)
{
    if(!game_on)return;
    if(skill_scanner())draw_vision(cam,view);
    cheat_rect={};if(cheat_open)draw_cheats(view);
    int x=(int)view.x+16;int y=(int)view.y+64;
    rl::draw_rectangle(x,y,260,16,{29,32,33,200});rl::draw_rectangle(x+2,y+2,(int)(256*player_hp/100),12,player_hp>35?ui::GOOD:ui::BAD);
    ui::text(rl::text_format("HULL %d",(int)player_hp),x+268,y+1,14,ui::TEXT);
    int enemies=0;for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER)enemies++;
    ui::text(rl::text_format("creatures %d%s%s",enemies,god?"   GOD MODE":"",auto_aim?"   AUTO AIM (cheat)":""),x,y+24,13,ui::MUTED);
    int sy=skills_hud(x,y+44,view,cam);
    weapons_hud(x,sy);
    if(game_room_count)minimap_draw(view);
    shop_draw_ui(view);
    if(tp_active()&&!skills_open)tp_draw_crosshair(view);
    ui::text(third_person?"V  top-down view":"V  third person",(int)view.x+16,(int)(view.y+view.height)-28,13,ui::MUTED);
    if(popup_t>0)
    {
        // Pickup toast: pops in, holds, fades; upper middle of the view.
        float age=POPUP_TIME-popup_t;float a=math::min(1.0f,math::min(age/0.12f,popup_t/0.5f));float pop=1+0.25f*math::max(0.0f,1-age/0.18f);
        int ts=(int)(26*pop);int tw=ui::text_width(popup_title,ts);int iw=ui::text_width(popup_info,14);int w=math::max(tw,iw)+48;
        int cx=(int)(view.x+view.width/2);int cy=(int)(view.y+view.height*0.22f)-(int)(8*(1-a));
        rl::draw_rectangle_rounded({(float)(cx-w/2),(float)cy,(float)w,(float)(ts+36)},0.25f,6,{29,32,33,(char)(225*a)});
        rl::RLColor c=vpt::color(popup_color|0xff000000u);c[3]=(char)(255*a);rl::draw_rectangle(cx-w/2+10,cy+10,5,ts+16,c);
        rl::RLColor t=ui::TEXT;t[3]=(char)(255*a);rl::RLColor mu=ui::MUTED;mu[3]=(char)(255*a);
        ui::text(popup_title,cx-tw/2+6,cy+8,ts,t);ui::text(popup_info,cx-iw/2+6,cy+12+ts,14,mu);
    }
    if(hurt>0)
    {
        // Getting hit must be unmistakable: red flash, thick vignette that fades.
        float h=math::min(hurt,1.0f);rl::draw_rectangle_rec(view,{200,20,10,(char)(h*h*60)});
        for(int k=0;k<6;k++) { float w=10+(float)k*12;rl::draw_rectangle_lines_ex({view.x+(float)k*12,view.y+(float)k*12,view.width-(float)k*24,view.height-(float)k*24},12,{220,30,20,(char)(h*(150-(float)k*24))}); }
    }
    enemy_feedback_hud(view,cam);
    foreach(t:dmg_texts)if(t.t>0)
    {
        rl::RLVector2 sp=rl::get_world_to_screen_ex(t.p,cam,(int)view.width,(int)view.height);
        ZString s=rl::text_format("-%d",(int)t.v);int fs=(int)(20+t.v*0.5f);float a=math::min(1.0f,t.t/0.3f);
        ui::text(s,(int)(view.x+sp[0])-ui::text_width(s,fs)/2+2,(int)(view.y+sp[1])+2,fs,{0,0,0,(char)(200*a)});
        ui::text(s,(int)(view.x+sp[0])-ui::text_width(s,fs)/2,(int)(view.y+sp[1]),fs,{255,70,50,(char)(255*a)});
    }
    if(game_over)
    {
        ZString t=game_over?"DESTROYED":"LAYER CLEARED";int w=ui::text_width(t,40);
        ui::text(t,(int)(view.x+view.width/2)-w/2,(int)(view.y+view.height/2)-40,40,game_over?ui::BAD:ui::ACCENT);
        ZString s=rl::text_format("R  new run      Esc  %s",ESC_TARGET);int sw2=ui::text_width(s,16);ui::text(s,(int)(view.x+view.width/2)-sw2/2,(int)(view.y+view.height/2)+16,16,ui::TEXT);
    }
    progression_hud(view);
    draw_skill_menu(view);
}

