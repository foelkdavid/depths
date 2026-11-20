module depths;
import std::math;
import raylib6::rl;
import vpt;

// Long-lived voices have explicit owners so a stolen/reused slot cannot be mistaken for our loop.
const int WIND_OWNER= -100;const int PORTAL_OWNER= -101;const int TELEPORT_OWNER= -102;
int wind_voice= -1;int portal_voice= -1;int teleport_voice= -1;
float gravel_cool;float creature_gravel_cool;int gravel_take;uint[vpt::MAX_RIGS] surface_gravel_phase;
fn bool environment_voice(int v,int owner,int sound)
{
    return v>=0&&v<audio::MAX_VOICES&&audio::voices[v].state==1&&audio::voices[v].owner==owner&&audio::voices[v].sound==sound;
}
fn void environment_audio_reset()
{
    // stop_all_sounds already cleared the voices; reset handles as well for a restart/layer change.
    wind_voice= -1;portal_voice= -1;teleport_voice= -1;gravel_cool=0;creature_gravel_cool=0;gravel_take=0;surface_gravel_phase={};
}
fn void environment_loop(int* handle,int sound,int owner,Vec pos,float gain,bool spatial,float dt,float muffled=0)
{
    bool owned=environment_voice(*handle,owner,sound);
    if(!owned)
    {
        *handle= -1;if(gain<=0)return;
        int v=audio::play_sound(sound,pos,0,1,spatial,true,0);if(v<0)return;
        audio::voices[v].owner=owner;*handle=v;
    }
    Voice* vc=&audio::voices[*handle];vc.pos=pos;vc.gain+=(gain-vc.gain)*vpt::clampf(dt*3,0,1);
    if(!spatial)vc.occlusion+=(muffled-vc.occlusion)*vpt::clampf(dt*2,0,1);
    audio::spatialize(vc);   // fades must also work after death, when there is no longer a tracked listener rig
    if(gain==0&&vc.gain<0.0005f&&math::abs(vc.gl)+math::abs(vc.gr)<0.002f) { vc.state=0;*handle= -1; }
}
fn void environment_audio_update(float dt)
{
    gravel_cool=math::max(0.0f,gravel_cool-dt);creature_gravel_cool=math::max(0.0f,creature_gravel_cool-dt);if(!audio::ready)return;
    bool alive=game_on&&!game_over&&!coming_soon&&player>=0&&player<vpt::rig_count;
    float wind=0;float shelter=0;
    if(alive&&gen_active&&gen_layer==0)
    {
        vpt::Rig* me=&vpt::rigs[player];int inside=surface_inside_cave({me.x,me.y,me.z});
        shelter=inside>=0?1.0f:0;wind=inside>=0?0.04f:0.26f;
    }
    environment_loop(&wind_voice,SND_WIND,WIND_OWNER,{},wind,false,dt,shelter);
    Vec pos=portal_base+(Vec){0,1.65f,0};float hum=0;
    if(alive&&portal_exists&&layer_clear)
    {
        vpt::Rig* me=&vpt::rigs[player];Vec dv=pos-(Vec){me.x,me.y+1,me.z};
        if(vpt::dot(dv,dv)<36*36)hum=0.65f*vpt::clampf(portal_age/1.6f,0,1);
    }
    environment_loop(&portal_voice,SND_PORTAL_IDLE,PORTAL_OWNER,pos,hum,true,dt);
    if(alive&&gen_active&&gen_layer==0)for(int r=0;r<vpt::rig_count;r++)if(kind[r]==STALKER)
    {
        vpt::Rig* e=&vpt::rigs[r];uint mask=0;int legs=vpt::rig_defs[e.def].leg_count;
        for(int l=0;l<legs;l++)if(e.phase[l]>=0)mask|=1u<<(uint)l;
        uint landed=surface_gravel_phase[r]&~mask;surface_gravel_phase[r]=mask;
        Vec dv=(Vec){e.x,e.y,e.z}-audio::listen_pos;
        if(!landed||vpt::dot(e.velocity,e.velocity)<0.1f||vpt::dot(dv,dv)>16*16)continue;
        for(int l=0;l<legs;l++)if(landed&(1u<<(uint)l)) { gravel_contact(e.foot[l],e.speed_mul>1.5f?0.34f:0.24f,true);break; }
    }
}
fn void gravel_contact(Vec foot,float volume= -1,bool creature=false)
{
    float* cooldown=creature?&creature_gravel_cool:&gravel_cool;
    if(!audio::ready||!gen_active||*cooldown>0)return;
    vpt::pick_floor=true;vpt::Pick ground=vpt::world_pick({foot+(Vec){0,0.18f,0},{0,-1,0}});vpt::pick_floor=false;
    if(!ground.hit||ground.distance>0.42f||ground.normal[1]<0.55f)return;
    if(ground.instance>=0&&!vpt::assets[vpt::instances[ground.instance].asset].generated)return; // metal crates/monuments aren't gravel
    gravel_take=(gravel_take+1+(int)(gr_servo()*4.99f))%6;
    audio::play_sound(SND_GRAVEL+gravel_take,foot,volume>=0?volume:gen_layer==0?0.24f:0.17f,0.86f+gr_servo()*0.18f,true,false,0);
    *cooldown=creature?0.16f:0.065f;   // a tripod landing is one ground crunch, not three simultaneous loud takes
}
fn void play_teleport(float cursor=0)
{
    if(!audio::ready||cursor<0||cursor>=(float)audio::bank[SND_TELEPORT].length-1)return;
    int v=audio::play_sound(SND_TELEPORT,{},cursor>0?0.0f:1.1f,1,false,false,0);
    if(v>=0) { audio::voices[v].owner=TELEPORT_OWNER;audio::voices[v].cursor=cursor;audio::voices[v].gain=1.1f;teleport_voice=v; }
}
fn float teleport_resume_cursor()
{
    return environment_voice(teleport_voice,TELEPORT_OWNER,SND_TELEPORT)?audio::voices[teleport_voice].cursor:-1;
}
