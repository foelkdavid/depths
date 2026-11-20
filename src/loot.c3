module depths;
import std::math;
import raylib6::rl;
import vpt;

// Explicit, finite container contents, not a random upgrade roll on every prop. Empty crates stay empty.
// Binding by saved position/path avoids transient generated-asset/instance IDs in scene files.
int[vpt::MAX_INSTANCES] prop_loot;
fn bool salvage_crate(int i) => ((ZString)&vpt::assets[vpt::instances[i].asset].path[0]).str_view().contains("service-crate");
fn void loot_init()
{
    for(int i=0;i<vpt::MAX_INSTANCES;i++)prop_loot[i]= -1;
    for(int k=0;k<game_item_count;k++)
    {
        GameItemFile it=game_items[k];int mod=it.kind>=1&&it.kind<=MOD_COUNT?it.kind-1:0;
        if(!it.contained) { add_pickup(it.x,it.z,mod);continue; }
        int crate= -1;float best=0.25f;
        for(int i=0;i<vpt::instance_count;i++)if(salvage_crate(i))
        {
            vpt::Instance p=vpt::instances[i];float ds=(p.x-it.x)*(p.x-it.x)+(p.z-it.z)*(p.z-it.z);
            if(ds<best) { best=ds;crate=i; }
        }
        if(crate>=0)prop_loot[crate]=mod;
    }
}
// A filled crate within reach of the robot (E opens it), or -1.
fn int crate_in_reach()
{
    if(player<0||player>=vpt::rig_count||game_over)return -1;vpt::Rig* me=&vpt::rigs[player];
    for(int i=0;i<vpt::instance_count;i++)if(prop_loot[i]>=0&&!vpt::hidden[i])
    { vpt::Instance p=vpt::instances[i];float dx=p.x-me.x;float dz=p.z-me.z;if(dx*dx+dz*dz<2.4f*2.4f&&math::abs(p.y-me.y)<1.5f)return i; }
    return -1;
}
// E at a crate: it opens and its perk (a free level in a random unlockable skill) lands at the robot's feet (picked up next frame: popup + sound).
fn void crate_interact()
{
    int id=crate_in_reach();if(id<0)return;
    int mod=prop_loot[id];prop_loot[id]= -1;vpt::Instance it=vpt::instances[id];vpt::Rig* me=&vpt::rigs[player];
    add_pickup(me.x,me.z,mod);flash({it.x,it.y+0.6f,it.z},brighten(PERK_COLOR,16),4,0.4f);
    audio::play_sound(SND_DOOR,{it.x,it.y+0.5f,it.z},0.7f,1.35f,true,false,0);
}
fn void release_crate_loot(int id)
{
    if(id<0||id>=vpt::instance_count||prop_loot[id]<0)return;
    int mod=prop_loot[id];prop_loot[id]= -1;vpt::Instance it=vpt::instances[id];
    add_pickup(it.x,it.z,mod);flash({it.x,it.y+0.5f,it.z},brighten(PERK_COLOR,16),3.5f,0.3f);
    audio::play_sound(SND_PICKUP,{it.x,it.y+0.5f,it.z},0.65f,0.85f,true,false,0);
}
