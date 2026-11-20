module depths;
import std::math;
import std::io;
import raylib6::rl;
import vpt;

// ---------------------------------------------------------------- --game-test (headless autopilot smoke test)
// Possesses the scene's robot, walks to the nearest creature, aims and fires for `seconds`, drawing real
// frames. Prints kills, debris, rooms cleared and frame times; fails loudly on a crash or a stuck state.
// Targeted deterministic ecology regression; use a detailed generated scene (e.g. seed 9).
bool test_ecology;
fn void ecology_check()
{
    god=true;
    int perched=0;int nest= -1;int flutter= -1;
    for(int r=0;r<vpt::rig_count;r++)
    {
        if(kind[r]==SKITTER&&vpt::rigs[r].oriented)perched++;
        if(kind[r]==NEST&&vpt::rigs[r].oriented)nest=r;
        if(kind[r]==FLUTTER)flutter=r;
    }
    assert(perched>0,"Ecology: skitters must start on walls/ceilings.");
    assert(nest>=0&&flutter>=0,"Ecology fixture needs an elevated nest and cave-wing.");
    int before=stat_hatches;
    for(int f=0;f<40;f++)update_nest(nest,0.5f,{1000,0,1000},true);
    assert(stat_hatches>before,"Unaware elevated nests must hatch without seeing the player.");
    assert(!aware[nest],"An off-screen nest must not aggro merely because it hatched.");
    int hatches=stat_hatches;kill_rig(nest,{0,0,1});
    assert(stat_brood_bursts>=5&&stat_hatches>=hatches+5,"Nest destruction must release at least five babies.");
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SKITTER)assert(aware[r]&&brood[r].alarm,"Nest damage must alarm the entire swarm.");
    int skitter= -1;flutter= -1;
    for(int r=0;r<vpt::rig_count;r++) { if(kind[r]==SKITTER)skitter=r;if(kind[r]==FLUTTER)flutter=r; }
    assert(skitter>=0&&flutter>=0);
    vpt::Rig* me=&vpt::rigs[player];Vec target={me.x,me.y,me.z};
    vpt::Pick roof=vpt::world_pick({target+(Vec){0,0.7f,0},{0,1,0}});
    assert(roof.hit&&roof.distance<9,"Ecology fixture needs a roof above the robot.");
    vpt::Rig* calm=&vpt::rigs[skitter];Vec cp=roof.point;
    calm.x=cp[0];calm.y=cp[1];calm.z=cp[2];vpt::set_surface(calm,{0,-1,0});
    aware[skitter]=false;brood[skitter].alarm=false;brood[skitter].suspicion=0;brood[skitter].scatter=0;
    for(int f=0;f<180;f++)(void)update_skitter(skitter,1.0f/60,cp+(Vec){0,-8,0},true,false);
    assert(!aware[skitter],"Passive distant sight must not turn ambient skitters into attackers.");
    for(int f=0;f<180&&!aware[skitter];f++)(void)update_skitter(skitter,1.0f/60,cp+(Vec){0,-1,0},true,false);
    assert(aware[skitter]&&brood[skitter].scatter>0&&!calm.hunting,"A disturbed skitter must scuttle away before charging.");
    vpt::Rig* s=&vpt::rigs[skitter];s.x=roof.point[0];s.y=roof.point[1];s.z=roof.point[2];
    vpt::set_surface(s,{0,-1,0});s.climb_time=0;s.climb_stay=60;s.airborne=false;
    brood[skitter].leap=0;brood[skitter].scatter=0;aware[skitter]=true;
    assert(!short_skitter_hop(s,target),"High ceilings must not allow long diving attacks.");
    for(int f=0;f<180;f++)(void)update_skitter(skitter,1.0f/60,target,true,false);
    assert(!s.airborne&&s.oriented&&s.patrol,"Alerted ceiling skitters must keep scuttling instead of diving or freezing.");
    assert(stat_leaps==0,"No jump should bridge a large vertical gap.");
    // Exercise the short-hop trajectory explicitly, without relying on a rare random decision.
    s.x=target[0]+0.8f;s.y=target[1]+0.75f;s.z=target[2];vpt::set_surface(s,{-1,0,0});
    assert(short_skitter_hop(s,target),"Nearby low wall hops should remain possible.");
    hop_skitter(skitter,target);
    assert(s.airborne&&brood[skitter].leap>=10,"A short hop must launch and impose a long cooldown.");
    for(int f=0;f<120;f++)vpt::update_rigs(1.0f/60);
    assert(!s.airborne&&s.y<target[1]+0.9f,"A short hop must land.");
    assert(vision_class(FLUTTER).str_view()=="flutter"&&vision_class(BLOATER).str_view()=="bloater","Vision must distinguish creature classes.");
    // Ambient cave-wing flights must happen without an alarm or damage.
    assert(vpt::rig_defs[vpt::rigs[flutter].def].wing_count==4,"Cave-wings need four animated wings.");
    aware[flutter]=false;brood[flutter].alarm=false;brood[flutter].think=0;
    int flights=stat_flights;
    for(int f=0;f<600;f++) { update_flutter(flutter,1.0f/60,{1000,0,1000},true,false);vpt::update_rigs(1.0f/60); }
    assert(stat_flights>flights&&!aware[flutter],"Cave-wings must make idle flights without attacking.");
    vpt::Rig* flyer=&vpt::rigs[flutter];Vec fp={flyer.x,flyer.y,flyer.z};
    hit_rig(flutter,fp,{0,0,1},0.1f);
    assert(aware[flutter]&&brood[flutter].alarm,"An injured cave-wing must defend itself.");
    int props=0;
    for(int i=0;i<vpt::instance_count;i++)
    {
        if(vpt::assets[vpt::instances[i].asset].generated) { assert(!destructible(i));continue; }
        assert(destructible(i),"Every placed asset, including kit/flat/large pieces, must be breakable.");
        if(props++==0) { damage_prop(i,{0,0,1},100);assert(vpt::hidden[i],"Placed assets must actually break."); }
    }
    assert(props>0);
    if(audio::ready)for(int k=SND_FLUTTER_DEATH;k<=SND_FLUTTER_FLAP;k++)assert(audio::bank[k].from_file&&audio::bank[k].length>0,"Cave-wing audio must load from the supplied recordings.");
    io::printfn("VPT ECOLOGY CHECKS PASSED: %d starting surface skitters, %d hatches, %d burst babies, %d leaps, %d flights, %d breakable props",perched,stat_hatches,stat_brood_bursts,stat_leaps,stat_flights,props);
}
bool test_all_mods;   // --game-test-mods: every modifier at level 2
fn void game_test(ZString path,float seconds)
{
    if(test_mechs) { mech_checks();return; }
    if(test_bestiary) { bestiary_checks();return; }
    if(is_gen_spec(path)) { if(!open_gen_spec(path)) { io::printfn("VPT GAME TEST: could not generate %s",path);return; } }
    else if(!vpt::load_scene(path)) { io::printfn("VPT GAME TEST: could not load %s",path);return; }
    int robot= -1;for(int r=0;r<vpt::rig_count;r++)if(is_player_rig(r))robot=r;
    if(robot<0) { io::printn("VPT GAME TEST: no robot in the scene");return; }
    vpt::begin_undo();vpt::controlled_rig=robot;game_start();if(!game_on) { io::printn("VPT GAME TEST: game did not start");return; }
    if(test_environment_audio) { environment_audio_checks();return; }
    if(test_ecology) { ecology_check();game_stop();return; }
    if(test_layers) { layer_checks();game_stop();return; }
    if(test_boss_v) { boss_v_bench();game_stop();return; }
    if(test_habitat) { if(gen_layer==0) { habitat_surface_check(); } else { habitat_flutter_check(); }game_stop();return; }
    if(test_aim) { aim_geometry_check();auto_aim=true;god=true; }
    if(test_all_mods)for(int k=0;k<SK_COUNT;k++)skill[k]=SKILLS[k].max;
    int start_creatures=0;for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER)start_creatures++;
    double w_update=0;double w_rigs=0;double w_post=0;double w_draw=0;
    int frames=(int)(seconds*60);double worst=0;double total=0;int max_debris=0;int max_lights=0;int shots=0;int rooms_cleared=0;bool any_locked=false;
    rl::RLRectangle view={0,0,960,540};
    for(int f=0;f<frames&&game_on&&!game_over;f++)
    {
        double t0=rl::get_time();float dt=1.0f/60;
        vpt::Rig me=vpt::rigs[player];int best= -1;float bd=1e9f;
        for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER) { float dx=vpt::rigs[r].x-me.x;float dz=vpt::rigs[r].z-me.z;float d=dx*dx+dz*dz;if(d<bd) { bd=d;best=r; } }
        vpt::control_input={};rl::RLRay ray={{me.x,me.y+8,me.z},{0,-1,0}};bool fire=false;
        if(best>=0)
        {
            vpt::Rig e=vpt::rigs[best];Vec target={e.x,e.y+0.25f*e.scale,e.z};Vec from=target+(Vec){0,6,0};
            ray={from,{0,-1,0}};float d=math::sqrt(bd);fire=d<11;
            if(d>5) { Vec to=nrm((Vec){e.x-me.x,0,e.z-me.z});vpt::control_input=to; }
        }
        if(fire&&fire_cool<=0&&rocket_charge<=0)shots++;
        if(audio::ready) { rl::RLCamera3D ac={.position={me.x+6,me.y+14,me.z+6},.target={me.x,me.y,me.z},.up={0,1,0},.fovy=40};audio_update({me.x,me.y+1,me.z},ac); }
        double s0=rl::get_time();game_update(dt,ray,true,fire);if(!game_on||game_over)break;double s1=rl::get_time();apply_layer_transition();vpt::update_rigs(dt);double s2=rl::get_time();game_post(dt);double s3=rl::get_time();
        if(f%6==0) { rl::RLCamera3D cam={.position={me.x+6,me.y+14,me.z+6},.target={me.x,me.y,me.z},.up={0,1,0},.fovy=40,.projection=rl::RLCameraProjection.PERSPECTIVE};rl::begin_drawing();vpt::draw_scene(cam,view);rl::end_drawing(); }
        double s4=rl::get_time();if(f>30) { w_update=math::max(w_update,s1-s0);w_rigs=math::max(w_rigs,s2-s1);w_post=math::max(w_post,s3-s2);w_draw=math::max(w_draw,s4-s3); }
        double t=rl::get_time()-t0;if(f>30)worst=math::max(worst,t);total+=t;max_debris=math::max(max_debris,debris_count);max_lights=math::max(max_lights,vpt::game_light_count);
        for(int k=0;k<game_room_count;k++)if(room_locked[k])any_locked=true;
    }
    for(int k=0;k<game_room_count;k++)if(room_clear[k]&&game_rooms[k].kind!=1)rooms_cleared++;
    int left=0;for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER)left++;
    io::printfn("VPT GAME TEST: %d creatures -> %d left (nests spawn more), %d shots, hull %.0f%s, rooms cleared %d/%d%s, max debris %d, max game lights %d, frame avg %.2f ms worst %.2f ms",
        start_creatures,left,shots,player_hp,game_over?" (destroyed)":"",rooms_cleared,math::max(game_room_count-1,0),any_locked?" (doors locked during fights)":"",max_debris,max_lights,total*1000/math::max(frames,1),worst*1000);
    io::printfn("VPT GAME TEST: worst stage ms: game %.1f, rigs %.1f, post %.1f, draw %.1f",w_update*1000,w_rigs*1000,w_post*1000,w_draw*1000);
    int playing=0;for(int v=0;v<audio::MAX_VOICES;v++)if(audio::voices[v].state==1)playing++;
    if(audio::ready)io::printfn("VPT GAME TEST: audio: %d voices playing, room feedback %.2f wet %.2f predelay %.0f ms",playing,audio::room_feedback,audio::room_wet,audio::room_predelay*1000);
    io::printfn("VPT GAME TEST: stats: %d impacts, %d kills, %d props destroyed, %d debris spawned, %d attacks on the robot",stat_impacts,stat_kills,stat_props,stat_debris,stat_attacks);
    io::printfn("VPT GAME TEST: ecology: %d hatches, %d burst babies, %d leaps, %d surface-skitter frames, %d cave-wing flights",stat_hatches,stat_brood_bursts,stat_leaps,stat_surface_skitters,stat_flights);
    game_stop();
    io::printfn("VPT GAME TEST: after stop: %d rigs, %d instances, %d dynamic objects (scene restored)",vpt::rig_count,vpt::instance_count,vpt::dyn_count);
}

// --bench-views SCENE: a generated layer from the top-down and the V (third person) camera, roof off/on.
fn void run_view_benchmark(ZString path)
{
    if(is_gen_spec(path)) { if(!open_gen_spec(path))return; } else { if(!vpt::load_scene(path))return; }
    vpt::show_grid=false;vpt::fixed_animation=true;vpt::rigs_frozen=true;vpt::update_rigs(0);vpt::lighting.quality=1;
    Vec at=vpt::rig_count?(Vec){vpt::rigs[0].x,vpt::rigs[0].y+0.6f,vpt::rigs[0].z}:(Vec){0,0.6f,0};
    rl::RLCamera3D top={.position=at+(Vec){7,15,9},.target=at,.up={0,1,0},.fovy=40,.projection=rl::RLCameraProjection.PERSPECTIVE};
    rl::RLCamera3D low={.position=at+(Vec){0,0.8f,-2.8f},.target=at+(Vec){0,0.3f,5},.up={0,1,0},.fovy=65,.projection=rl::RLCameraProjection.PERSPECTIVE};
    for(int mode=0;mode<3;mode++)
    {
        set_roof_visible(mode==2);rl::RLCamera3D cam=mode==0?top:low;
        io::printfn("VPT VIEW BENCH: %s: %.2f ms at 640x360, %.2f ms at 1280x720 (bounces %d)",mode==0?"top-down":mode==1?"V without roof":"V with roof",vpt::bench_frames(cam,{0,0,640,360},30,false),vpt::bench_frames(cam,{0,0,1280,720},30,false),vpt::lighting.bounces);
    }
}
