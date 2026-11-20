module depths;
import std::math;
import std::io;
import raylib6::rl;
import vpt;

bool test_environment_audio;
fn int gravel_voices()
{
    int n=0;for(int v=0;v<audio::MAX_VOICES;v++)if(audio::voices[v].state==1&&audio::voices[v].sound>=SND_GRAVEL&&audio::voices[v].sound<SND_GRAVEL+6)n++;return n;
}
fn void environment_audio_checks()
{
    assert(audio::ready,"Audio test needs a working device (stream is muted).");
    assert(gen_layer==0,"Use surface:SEED for the environment sound test.");
    for(int k=SND_WIND;k<SND_COUNT;k++)assert(audio::bank[k].from_file&&audio::bank[k].length>0,"New effects must load from the supplied recordings.");
    vpt::Rig* me=&vpt::rigs[player];Vec spawn={me.x,me.y,me.z};
    rl::RLCamera3D cam={.position=spawn+(Vec){3,3,5},.target=spawn,.up={0,1,0},.fovy=45};audio_update(spawn+(Vec){0,1,0},cam);
    for(int f=0;f<80;f++)environment_audio_update(0.05f);
    assert(environment_voice(wind_voice,WIND_OWNER,SND_WIND)&&audio::voices[wind_voice].loop&&!audio::voices[wind_voice].spatial);
    float outside=audio::voices[wind_voice].gain;assert(outside>0.2f&&audio::voices[wind_voice].tsend==0,"Outdoor wind must be audible without room reverb.");
    assert(portal_voice<0,"Dormant rifts must not hum.");
    SurfaceCave c=surface_caves[0];me.x=c.center[0];me.y=0.12f;me.z=c.center[2]+2;
    for(int f=0;f<80;f++)environment_audio_update(0.05f);
    assert(audio::voices[wind_voice].gain<outside*0.3f&&audio::voices[wind_voice].occlusion>0.8f,"Surface cave wind must fade and become muffled.");
    me.x=spawn[0];me.y=spawn[1];me.z=spawn[2];
    for(int f=0;f<80;f++)environment_audio_update(0.05f);
    assert(audio::voices[wind_voice].gain>outside*0.95f,"Leaving a surface cave must restore outdoor wind.");
    int winds=0;for(int v=0;v<audio::MAX_VOICES;v++)if(audio::voices[v].state==1&&audio::voices[v].owner==WIND_OWNER)winds++;
    assert(winds==1,"Wind must use exactly one owned loop, not stack per frame.");
    gravel_cool=0;int contacts=gravel_voices();gravel_contact(me.foot[0]);
    assert(gravel_cool>0&&gravel_voices()==contacts+1,"A natural-ground foot landing must play one gravel take.");
    gravel_contact(me.foot[1]);assert(gravel_voices()==contacts+1,"A tripod contact must not stack three gravel takes.");
    int stalker= -1;for(int r=0;r<vpt::rig_count;r++)if(kind[r]==STALKER&&surface_inside_cave({vpt::rigs[r].x,vpt::rigs[r].y,vpt::rigs[r].z})<0) { stalker=r;break; }
    assert(stalker>=0);vpt::Rig* hunter=&vpt::rigs[stalker];Vec old_foot=hunter.foot[0];
    hunter.foot[0]={hunter.x,hunter.y,hunter.z};hunter.velocity={1,0,0};hunter.phase[0]= -1;surface_gravel_phase[stalker]=1;creature_gravel_cool=0;
    audio_update({hunter.x,hunter.y+1,hunter.z},cam);int npc_before=gravel_voices();environment_audio_update(0.05f);
    assert(creature_gravel_cool>0&&gravel_voices()==npc_before+1,"A nearby stalker landing must produce a gait-synced gravel contact.");
    hunter.foot[0]=old_foot;hunter.velocity={};surface_gravel_phase[stalker]=0;
    unlock_layer_exit();me.x=portal_base[0]+4;me.z=portal_base[2];me.y=portal_base[1];portal_age=2;
    audio_update({me.x,me.y+1,me.z},cam);
    for(int f=0;f<80;f++)environment_audio_update(0.05f);
    assert(environment_voice(portal_voice,PORTAL_OWNER,SND_PORTAL_IDLE)&&audio::voices[portal_voice].loop&&audio::voices[portal_voice].spatial&&audio::voices[portal_voice].gain>0.5f,"An awake nearby rift must have a positional looping drone.");
    int portal=portal_voice;me.x=portal_base[0]-40;
    for(int f=0;f<80;f++)environment_audio_update(0.05f);
    assert(portal_voice<0||audio::voices[portal].gain<0.001f,"Far-away rifts must fade out.");
    me.x=portal_base[0]+4;progression_update(0.05f);me.x=portal_base[0];progression_update(0.05f);
    assert(portal_fade>0&&environment_voice(teleport_voice,TELEPORT_OWNER,SND_TELEPORT)&&!audio::voices[teleport_voice].loop&&!audio::voices[teleport_voice].spatial,"Crossing must play the real teleport cue once, flat.");
    progression_update(1);assert(layer_pending);apply_layer_transition();
    assert(gen_layer== -1&&wind_voice<0&&portal_voice<0,"Descending must stop old surface wind and rift loops.");
    assert(environment_voice(teleport_voice,TELEPORT_OWNER,SND_TELEPORT),"The teleport cue tail must resume on arrival, not be cut by generation.");
    for(int f=0;f<30;f++)environment_audio_update(0.05f);
    assert(wind_voice<0,"Underground layer -1 must not start outdoor wind.");
    game_stop();for(int v=0;v<audio::MAX_VOICES;v++)assert(audio::voices[v].state==0,"Exiting play must release environmental loops and one-shots.");
    assert(wind_voice<0&&portal_voice<0&&teleport_voice<0);
    io::printn("VPT ENVIRONMENT AUDIO CHECKS PASSED: real files, wind shelter, one loop, gravel contacts, positional rift, crossing/arrival, layer cleanup");
}
