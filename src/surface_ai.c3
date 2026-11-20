module depths;
import std::math;
import raylib6::rl;
import vpt;

const int SURF_REST=0;const int SURF_FORAGE=1;const int SURF_GROOM=2;const int SURF_SOCIAL=3;const int SURF_PATROL=4;const int SURF_WATCH=5;
fn void surface_bite(int r,Vec target,float reach,float damage)
{
    vpt::Rig* e=&vpt::rigs[r];Vec to=target-(Vec){e.x,e.y,e.z};
    if(vpt::dot(to,to)>reach*reach||attack_cool[r]>0||!brood_sees(e,target+(Vec){0,0.5f,0}))return;
    attack_cool[r]=kind[r]==SCAVENGER?1.0f:1.5f;stat_attacks++;
    robot_hit(nrm(to),damage,kind[r]==SCAVENGER?0.65f:1.2f,species_of(r));
    audio::play_sound(kind[r]==SCAVENGER?SND_HATCH:SND_CRAWLER_ATTACK,{e.x,e.y+0.3f,e.z},1.1f,kind[r]==SCAVENGER?1.25f:0.8f,true,false,0);
    e.knock-=nrm(to)*1.5f;
    if(player_hp<=0) { player_hp=0;die(); }
}
// Disturbance = an instant, readable reaction (no random sight gate): a startle hop / rear-up with a cry, then
// fight or flight. Hit, the robot right next to it, gunfire close by or a shot landing near it all count.
// Scavengers: bold ones (or any that got hit) rush the robot at once and rouse the pack; shy ones bolt first
// and come back as a pack. Stalkers rear up and brace a charge immediately (no cooldown wait).
fn void surface_disturb(int r,Vec source,bool hit)
{
    if(r<0||r>=vpt::rig_count||(kind[r]!=SCAVENGER&&kind[r]!=STALKER))return;
    vpt::Rig* e=&vpt::rigs[r];BroodMind* b=&brood[r];Vec pos={e.x,e.y,e.z};Vec away=nrm((Vec){pos[0]-source[0],0,pos[2]-source[2]}+(Vec){0.0001f,0,0});
    bool fresh=!aware[r]||b.memory<3;aware[r]=true;b.memory=math::max(b.memory,hit?15.0f:10.0f);b.think=0;e.has_goal=false;e.wait=0;
    e.has_look_point=true;e.look_point=source+(Vec){0,0.5f,0};
    if(kind[r]==SCAVENGER)
    {
        if(fresh&&!e.airborne)
        {
            // startle: a short hop away from the threat, chittering
            vpt::detach_surface(e);e.airborne=true;e.air_time=0;e.jump_velocity=away*(hit?1.2f:2.0f)+(Vec){0,2.8f,0};
            audio::play_sound(SND_HATCH,pos,0.55f,1.35f+gr()*0.25f,true,false,0);
        }
        bool fight=hit||b.temperament>0.45f;
        if(fight) { b.alarm=true;b.scatter=0; } else { b.alarm=true;b.scatter=0.7f+(1-b.temperament)*0.8f; }
        // the pack hears it: neighbours within 10 m react too (one level deep, no chain storms)
        for(int k=0;k<vpt::rig_count;k++)if(k!=r&&kind[k]==SCAVENGER&&!aware[k])
        {
            Vec dv=(Vec){vpt::rigs[k].x-e.x,0,vpt::rigs[k].z-e.z};
            if(vpt::dot(dv,dv)<100) { aware[k]=true;brood[k].alarm=true;brood[k].memory=10;brood[k].think=0;brood[k].scatter=brood[k].temperament>0.45f?0:0.5f+gr()*0.6f;vpt::rigs[k].has_look_point=true;vpt::rigs[k].look_point=source+(Vec){0,0.5f,0}; }
        }
        return;
    }
    // stalker: rear up + roar, brace right away (unless already charging / braced)
    b.alarm=true;if(rush[r]>0||fuse[r]>=0)return;
    b.leap=0;
    if(fresh) { e.knock+=away*1.2f;audio::play_sound(SND_CRAWLER_ROAR,pos,is_layer_boss(r)?1.8f:1.2f,is_layer_boss(r)?0.65f:0.9f,true,false,0); }
}
fn Vec surface_spacing(int r)
{
    vpt::Rig* e=&vpt::rigs[r];Vec avoid={};
    for(int k=0;k<vpt::rig_count;k++)if(k!=r&&kind[k]==kind[r])
    {
        Vec d={e.x-vpt::rigs[k].x,0,e.z-vpt::rigs[k].z};float ds=vpt::dot(d,d);
        if(ds>0.01f&&ds<2.25f)avoid+=nrm(d)*(1-math::sqrt(ds)/1.5f);
    }
    return avoid;
}
fn Vec surface_food(int r)
{
    Vec home=brood[r].home;Vec food=home;float best=81;
    for(int i=0;i<vpt::instance_count;i++)
    {
        vpt::Instance p=vpt::instances[i];vpt::Asset* a=&vpt::assets[p.asset];if(a.generated||vpt::hidden[i])continue;
        String path=((ZString)&a.path[0]).str_view();
        if(!path.contains("bone-ribs")&&!path.contains("skull-fossil")&&!path.contains("service-crate")&&!path.contains("pod-succulent"))continue;
        Vec dv={p.x-home[0],0,p.z-home[2]};float ds=vpt::dot(dv,dv);
        if(ds<best) { best=ds;food={p.x,p.y,p.z}; }
    }
    return food;
}
fn int surface_companion(int r)
{
    vpt::Rig* e=&vpt::rigs[r];int friend= -1;float best=36;
    for(int k=0;k<vpt::rig_count;k++)if(k!=r&&kind[k]==kind[r]&&!aware[k])
    {
        Vec d={e.x-vpt::rigs[k].x,0,e.z-vpt::rigs[k].z};float ds=vpt::dot(d,d);
        if(ds<best) { best=ds;friend=k; }
    }
    return friend;
}
fn void surface_idle(int r,float dt)
{
    vpt::Rig* e=&vpt::rigs[r];BroodMind* b=&brood[r];Vec pos={e.x,e.y,e.z};bool scav=kind[r]==SCAVENGER;
    if(b.think<=0)
    {
        float roll=gr();float a=gr()*6.283f;b.think=scav?0.9f+gr()*2.2f:1.6f+gr()*3.0f;e.has_goal=false;e.wait=0;e.burst=1;
        if(scav)
        {
            b.activity=roll<0.1f?SURF_REST:roll<0.22f?SURF_GROOM:roll<0.6f?SURF_FORAGE:roll<0.82f?SURF_SOCIAL:SURF_PATROL;
            if(b.activity==SURF_FORAGE)
            { b.interest=surface_food(r);e.goal=b.interest+(Vec){math::cos(a)*1.0f,0,math::sin(a)*1.0f}+surface_spacing(r);e.has_goal=true; }
            else if(b.activity==SURF_SOCIAL)
            {
                int friend=surface_companion(r);
                b.interest=friend>=0?(Vec){vpt::rigs[friend].x,vpt::rigs[friend].y,vpt::rigs[friend].z}:b.home;
                e.goal=b.interest+(Vec){math::cos(a)*1.1f,0,math::sin(a)*1.1f}+surface_spacing(r);e.has_goal=true;
            }
        }
        else { b.activity=roll<0.6f?SURF_WATCH:SURF_PATROL;b.think=2.5f+gr()*4; }
        if(b.activity==SURF_PATROL) { e.goal=b.home+(Vec){math::cos(a)*(scav?2.8f:4.0f),0,math::sin(a)*(scav?2.8f:4.0f)};e.has_goal=true; }
        if(b.activity==SURF_GROOM&&b.chirp<=0)
        { audio::play_sound(SND_HATCH,pos,0.18f,0.9f+b.temperament*0.4f);b.chirp=6+gr()*5; }
    }
    e.speed_mul=(scav?0.62f:0.45f)+b.temperament*0.35f;
    Vec to=e.goal-pos;to[1]=0;if(e.has_goal&&vpt::dot(to,to)<0.2f)e.has_goal=false;
    // Sniffing around: arrived scavengers keep scuttling short darts around what they are busy with.
    if(scav&&!e.has_goal&&b.activity!=SURF_REST&&b.activity!=SURF_GROOM&&gr()<dt*3.2f)
    {
        float a2=gr()*6.283f;float d2=0.5f+gr()*1.3f;Vec c=b.activity==SURF_PATROL?pos:b.interest;
        e.goal=c+(Vec){math::cos(a2)*d2,0,math::sin(a2)*d2}+surface_spacing(r);e.has_goal=true;e.burst=0.7f+gr()*0.6f;e.wait=0;
    }
    if(e.has_goal&&vpt::blocked(e.goal[0],e.goal[2],e.y,0.3f)) { e.has_goal=false;b.think=math::min(b.think,0.8f); }
    e.patrol=e.has_goal&&(b.activity==SURF_FORAGE||b.activity==SURF_SOCIAL||b.activity==SURF_PATROL);
    e.has_look_point=b.activity!=SURF_REST;
    if(b.activity==SURF_GROOM) { e.look_point=pos+vpt::rig_dir(e,{math::sin(e.time*3.4f)*0.4f,-0.12f,0.45f}); }
    else if(b.activity==SURF_FORAGE||b.activity==SURF_SOCIAL) { e.look_point=b.interest+(Vec){0,b.activity==SURF_FORAGE?0.05f:0.3f,0}; }
    else { e.look_point=pos+vpt::rig_dir(e,{math::sin(e.time*0.7f+(float)r)*5,0.4f,6}); }
}
fn void surface_flank(int r,Vec target,Vec to)
{
    vpt::Rig* e=&vpt::rigs[r];BroodMind* b=&brood[r];Vec pos={e.x,e.y,e.z};
    if(b.think<=0||!e.has_goal)
    {
        Vec side=nrm((Vec){-to[2],0,to[0]})*(b.temperament>0.5f?1.0f:-1.0f);
        e.goal=pos+side*(0.8f+b.temperament)-nrm(to)*0.4f+surface_spacing(r);e.has_goal=true;e.burst=1;e.wait=0;b.think=0.8f+gr();
    }
    e.patrol=true;e.speed_mul=0.55f;e.has_look_point=true;e.look_point=target+(Vec){0,0.5f,0};
}
fn void update_surface_creature(int r,float dt,Vec target,bool active,bool firing)
{
    vpt::Rig* e=&vpt::rigs[r];BroodMind* b=&brood[r];Vec pos={e.x,e.y,e.z};Vec to=target-pos;to[1]=0;float ds=vpt::dot(to,to);
    e.hunting=false;e.patrol=false;b.think-=dt;b.leap-=dt;b.chirp-=dt;b.memory=math::max(0.0f,b.memory-dt);
    if(!active)return;
    if(b.alarm&&b.memory<=0&&ds>144) { b.alarm=false;aware[r]=false;b.think=0; }
    if(!aware[r]&&(ds<(kind[r]==SCAVENGER?12.25f:30.0f)||(firing&&ds<144))) { surface_disturb(r,target,false); }
    if(!aware[r]&&gr()<dt*3&&ds<(kind[r]==SCAVENGER?81:196)&&brood_sees(e,target+(Vec){0,0.5f,0}))
    {
        if(ds<(kind[r]==SCAVENGER?9:64)||firing)
        {
            aware[r]=true;b.think=0;b.memory=6;
            if(kind[r]==SCAVENGER)b.scatter=1.1f+(1-b.temperament)*1.4f;
        }
        else { b.activity=SURF_WATCH;e.has_look_point=true;e.look_point=target+(Vec){0,0.6f,0}; }
    }
    if(b.scatter>0)
    {
        b.scatter=math::max(0.0f,b.scatter-dt);e.speed_mul=1.35f+(1-b.temperament)*0.6f;
        if(b.think<=0||!e.has_goal)
        { float a=gr()*6.283f;e.goal=pos-nrm(to)*3+(Vec){math::cos(a),0,math::sin(a)}+surface_spacing(r);e.has_goal=true;e.wait=0;e.burst=1;b.think=0.35f; }
        e.patrol=true;e.has_look_point=true;e.look_point=target;
        if(b.scatter<=0&&!b.alarm&&ds>25) { aware[r]=false;b.think=0; }
        return;
    }
    if(!aware[r]) { surface_idle(r,dt);return; }
    if(ds>400&&!b.alarm) { aware[r]=false;b.think=0;return; }
    if(kind[r]==SCAVENGER)
    {
        if(b.alarm)for(int k=0;k<vpt::rig_count;k++)if(kind[k]==SCAVENGER&&!aware[k])
        { Vec dv=(Vec){vpt::rigs[k].x,0,vpt::rigs[k].z}-(Vec){e.x,0,e.z};if(vpt::dot(dv,dv)<100) { aware[k]=true;brood[k].scatter=0.5f+(1-brood[k].temperament);brood[k].memory=6; } }
        // Shy scavengers keep their distance; bold ones probe/flank. Shooting provokes a real pack response.
        if(!b.alarm&&ds>12&&b.temperament<0.65f) { surface_flank(r,target,to);return; }
        Vec side=nrm((Vec){-to[2],0,to[0]});e.hunting=true;e.hunt_stop=0.65f;
        e.hunt_target=target+side*(math::sin(e.time*2.2f+(float)r)*1.1f)+surface_spacing(r);e.speed_mul=1.05f+b.temperament*0.45f;
        surface_bite(r,target,0.95f,5);return;
    }
    // Patient ridge sentries: brace, committed charge, then recover/reposition instead of homing nonstop.
    bool elder=is_layer_boss(r);e.has_look_point=true;e.look_point=target+(Vec){0,0.7f,0};
    if(rush[r]>0)
    {
        rush[r]-=dt;e.hunting=true;e.hunt_target=b.perch;e.hunt_stop=0.3f;e.speed_mul=elder?2.5f:2.8f;
        surface_bite(r,target,elder?1.9f:1.25f,elder?24:12);
        if(rush[r]<=0) { b.leap=3.5f+gr()*2;b.think=0;e.speed_mul=0.7f; }
        return;
    }
    if(fuse[r]>=0)
    {
        fuse[r]-=dt;e.speed_mul=0.5f;
        if(fuse[r]<=0) { fuse[r]= -1;rush[r]=elder?1.2f:0.9f;b.perch=target;if(player>=0)b.perch+=vpt::rigs[player].velocity*0.25f; }
        return;
    }
    if(ds<196&&ds>2&&b.leap<=0&&brood_sees(e,target+(Vec){0,0.6f,0}))
    {
        fuse[r]=elder&&hp[r]<35?0.55f:0.85f;
        audio::play_sound(SND_CRAWLER_ROAR,pos,elder?1.8f:1.1f,elder?0.65f:0.85f,true,false,0);
        for(int i=0;i<6;i++)spawn_debris(pos+(Vec){0,0.1f,0},rand_dir()*1.5f+(Vec){0,1,0},0.035f,0x62849d,0,0.65f);
        return;
    }
    if(b.leap>0&&ds<196) { surface_flank(r,target,to);return; }
    e.hunting=true;e.hunt_target=target;e.hunt_stop=3.5f;e.speed_mul=0.55f+b.temperament*0.25f;
    if(ds<3)surface_bite(r,target,elder?1.9f:1.25f,elder?18:9);
}
