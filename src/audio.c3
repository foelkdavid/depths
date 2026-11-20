module depths;
import std::math;
import raylib6::rl;
import vpt;
import vpt::audio;

// Depths sounds on the engine mixer (vpt::audio): the slot table (registered in this order, so the SND_*
// numbers are the engine sound ids), per-sound reach, and the robot's servo whirs. Only real files play:
// assets/sounds/<name>.wav|ogg|mp3|flac (originals and splicing: dev/tools/prepare-sounds.py).
// Sound slots; the name is the file looked up in assets/sounds/. Variants are consecutive slots.
const int SND_SHOT=0;           // gun_shot_1..6
const int SND_ROCKET=6;const int SND_BOOM=7;const int SND_HIT_ROCK=8;const int SND_HIT_FLESH=9;const int SND_SPLAT=10;
const int SND_NEST=11;const int SND_STEP=12;const int SND_DOOR=13;const int SND_PICKUP=14;const int SND_HURT=15;const int SND_RICOCHET=16;
const int SND_SCREECH=17;const int SND_AMBIENCE=18;const int SND_DEATH=19;
const int SND_SERVO=20;         // robot_servo_1..8
const int SND_MUSIC=28;
const int SND_FOOT=29;          // robot_foot_1..8
const int SND_CRAWLER_ATTACK=37;const int SND_CRAWLER_ROAR=38;const int SND_CRAWLER_WALK=39;
const int SND_SKITTER_CRAWL=40; // skitter_crawl_loop_1..3
const int SND_HATCH=43;const int SND_GAME_OVER=44;const int SND_ROBOT_HIT=45;const int SND_FLUTTER_DEATH=51;const int SND_FLUTTER_CLICK=52;const int SND_FLUTTER_FLAP=55;const int SND_WIND=56;const int SND_PORTAL_IDLE=57;const int SND_TELEPORT=58;const int SND_GRAVEL=59;const int SND_SHOTGUN=65;const int SND_WEAPON_WHIR=68;const int SND_WEAPON_LATCH=71;const int SND_MENU_MUSIC=74;const int SND_COUNT=75;   // robot_hit_1..6
const ZString[SND_COUNT] SND_NAMES={"gun_shot_1","gun_shot_2","gun_shot_3","gun_shot_4","gun_shot_5","gun_shot_6",
    "missile_launch","missile_explosion","impact_rock","impact_flesh","enemy_death_splatter","nest_burst_squelch","footstep","door_clank",
    "item_pickup","robot_hurt","ricochet","skitter_attack","ambience","robot_death",
    "robot_servo_1","robot_servo_2","robot_servo_3","robot_servo_4","robot_servo_5","robot_servo_6","robot_servo_7","robot_servo_8",
    "music","robot_foot_1","robot_foot_2","robot_foot_3","robot_foot_4","robot_foot_5","robot_foot_6","robot_foot_7","robot_foot_8",
    "crawler_attack","crawler_roar","crawler_walk_loop","skitter_crawl_loop_1","skitter_crawl_loop_2","skitter_crawl_loop_3","skitter_hatch_squish","game_over","robot_hit_1","robot_hit_2","robot_hit_3","robot_hit_4","robot_hit_5","robot_hit_6","flutter_death","flutter_click_1","flutter_click_2","flutter_click_3","flutter_flap_loop","surface_wind_loop","portal_idle_loop","teleport","gravel_step_1","gravel_step_2","gravel_step_3","gravel_step_4","gravel_step_5","gravel_step_6",
    "shotgun_1","shotgun_2","shotgun_3","weapon_whir_1","weapon_whir_2","weapon_whir_3","weapon_latch_1","weapon_latch_2","weapon_latch_3","menu_music"};
// Distance (m) over which a sound halves-ish: big combat events carry across the room.
fn float reach(int k) => k==SND_PORTAL_IDLE?8.0f:k>=SND_GRAVEL&&k<SND_GRAVEL+6?7.0f:k==SND_SPLAT||k==SND_BOOM||k==SND_NEST||k==SND_CRAWLER_ROAR||k==SND_CRAWLER_ATTACK?18.0f:k==SND_CRAWLER_WALK?16.0f:k>=SND_SKITTER_CRAWL&&k<SND_SKITTER_CRAWL+3?11.0f:5.0f;
fn void register_sounds()
{
    if(audio::sound_count)return;
    for(int k=0;k<SND_COUNT;k++)
    {
        bool dry=k==SND_MUSIC||k==SND_MENU_MUSIC||k==SND_WIND;   // music and wind: no room reverb
        (void)audio::register_sound(SND_NAMES[k],reach(k),dry,k==SND_WIND);
    }
}
fn void audio_init() { register_sounds();audio::init(); }
fn void audio_close() => audio::close();
fn void audio_update(Vec ear,rl::RLCamera3D cam) => audio::update(ear,cam);
fn void stop_all_sounds() { audio::stop_all();servo_ready=false;environment_audio_reset(); }
fn float jitter(float amount) => 1+(gr()-0.5f)*2*amount;

// ---------------------------------------------------------------- servos
// One quiet mechanical layer per leg, driven by the solved local coxa/femur/tibia angles.
// Local rotations exclude rigid world translation/yaw: aiming on planted feet still drives the IK.
vpt::Quat[vpt::MAX_RIG_PARTS] servo_prev;
int[12] servo_voice;int[12] servo_choice;float[12] servo_speed;float[12] servo_quiet;float[12] servo_rest;
const int SERVO_MAX_VOICES=2;   // the robot never whirs on all legs at once
bool servo_ready;uint servo_rng=9173;   // audio variation must not advance the combat RNG
fn float gr_servo() { servo_rng=servo_rng*1664525u+1013904223u;return (float)(servo_rng>>8)/16777216.0f; }
fn void robot_servos(vpt::Rig* r,float dt,bool enabled=true)
{
    if(!audio::ready)return;
    vpt::RigDef* d=&vpt::rig_defs[r.def];
    if(!servo_ready)
    {
        servo_prev=r.joint_rotation;for(int l=0;l<12;l++) { servo_voice[l]= -1;servo_choice[l]=l%4;servo_speed[l]=0;servo_quiet[l]=0;servo_rest[l]=0; }
        servo_ready=true;return;   // no false movement on spawn / restart
    }
    int busy=0;for(int l=0;l<12;l++) { int v=servo_voice[l];if(v>=0&&audio::voices[v].state==1&&audio::voices[v].tag==l+1)busy++; }
    for(int l=0;l<d.leg_count&&l<12;l++)
    {
        servo_rest[l]-=dt;
        vpt::RigLeg leg=d.legs[l];int[3] parts={leg.coxa,leg.femur,leg.tibia};float speed=0;
        foreach(p:parts)if(p>=0)
        {
            vpt::Quat a=servo_prev[p];vpt::Quat b=r.joint_rotation[p];
            float sign=a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w<0?-1.0f:1.0f;
            float x=a.x-b.x*sign;float y=a.y-b.y*sign;float z=a.z-b.z*sign;float w=a.w-b.w*sign;
            speed+=2*math::sqrt(x*x+y*y+z*z+w*w)/math::max(dt,0.001f);
        }
        // Attack follows joint speed; short release + hysteresis prevents IK noise chattering.
        servo_speed[l]+=(math::min(speed,20.0f)-servo_speed[l])*(1-math::exp(-dt/0.025f));
        int v=servo_voice[l];bool owned=v>=0&&audio::voices[v].state==1&&audio::voices[v].tag==l+1;
        if(v>=0&&!owned&&servo_voice[l]>=0) { servo_voice[l]= -1;servo_rest[l]=0.25f+gr_servo()*0.45f; }   // stroke finished: pause before the next
        bool moving=enabled&&dt>0&&dt<0.15f&&servo_speed[l]>(owned?0.3f:0.8f);
        servo_quiet[l]=moving?0:servo_quiet[l]+dt;
        if(!moving)
        {
            if(owned) { audio::voices[v].gain=0;if(servo_quiet[l]>0.04f) { audio::voices[v].state=0;servo_voice[l]= -1;busy--; } }
            continue;
        }
        float drive=vpt::clampf(servo_speed[l]/7,0,1);
        float gain=0.04f+0.10f*math::sqrt(drive);float pitch=0.82f+drive*0.38f+(float)(l%3)*0.025f;
        Vec pos=vpt::rig_to_world(r,leg.hip);
        if(!owned)
        {
            if(servo_rest[l]>0||busy>=SERVO_MAX_VOICES)continue;
            // Short corrections vs longer loaded strokes; never repeat the same take consecutively.
            servo_choice[l]=(servo_choice[l]+1+(int)(gr_servo()*2.99f))%4;
            int k=SND_SERVO+(drive>0.6f?4:0)+servo_choice[l];
            v=audio::play_sound(k,pos,gain,pitch,true,false,0);servo_voice[l]=v;
            if(v>=0) { audio::voices[v].tag=l+1;busy++; }
        }
        else { audio::voices[v].pos=pos;audio::voices[v].gain=gain;audio::voices[v].rate=pitch; }
    }
    servo_prev=r.joint_rotation;
}
