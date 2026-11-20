module depths;
import std::math;
import std::io;
import raylib6::rl;
import vpt;

bool test_layers;bool test_aim;
fn void aim_geometry_check()
{
    vpt::update_rigs(0);int hits=0;int elevated=0;
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER)
    {
        vpt::Rig* e=&vpt::rigs[r];Vec center=vpt::rig_to_world(e,{0,0.4f,0});
        for(int attempt=0;attempt<5;attempt++)
        {
            float a=(float)attempt*1.2566f;Vec from=center+vpt::rig_dir(e,{math::cos(a)*1.4f,1.2f,math::sin(a)*1.4f});
            Vec point;if(!auto_aim_point(r,from,&point))continue;
            vpt::Pick hit=vpt::pick_scene({from,nrm(point-from)},-1,true,player);
            assert(hit.hit&&hit.rig==r,"Auto aim must target occupied posed voxels, including correct height/orientation.");
            hits++;if(e.oriented)elevated++;break;
        }
    }
    assert(hits>=3,"Auto-aim fixture must exercise several creature shapes.");
    if(gen_layer== -1&&gen_active)assert(elevated>0,"Auto aim must cover elevated wall/ceiling geometry.");
    Vec[vpt::MAX_RIGS] velocity;
    for(int r=0;r<vpt::rig_count;r++) { velocity[r]=vpt::rigs[r].velocity;vpt::rigs[r].velocity={}; }
    int muzzle_hits=0;Vec from=muzzle(1-barrel);
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]!=NONE&&kind[r]!=PLAYER)
    {
        Vec point;Vec locked;if(!auto_aim_point(r,from,&point)||!auto_target(from,point,&locked))continue;
        vpt::Pick shot=vpt::pick_scene({from,nrm(locked-from)},-1,true,player);
        assert(shot.hit&&shot.rig>=0&&kind[shot.rig]!=PLAYER,"A static auto-aim lock must produce a real muzzle-to-creature hit, not a floor/wall hit.");muzzle_hits++;
    }
    for(int r=0;r<vpt::rig_count;r++)vpt::rigs[r].velocity=velocity[r];
    io::printfn("VPT AIM GEOMETRY CHECKS PASSED: %d creatures, %d elevated targets, %d real-muzzle hits",hits,elevated,muzzle_hits);
}
fn int check_boss()
{
    for(int r=0;r<vpt::rig_count;r++)if(is_layer_boss(r))return r;return -1;
}
fn void capture_rift(ZString path)
{
    vpt::show_grid=false;vpt::lighting.quality=1;
    Vec at=portal_base+(Vec){0,1.5f,0};rl::RLCamera3D cam={.position=at+(Vec){3.3f,1.4f,5.8f},.target=at,.up={0,1,0},.fovy=48,.projection=rl::RLCameraProjection.PERSPECTIVE};
    for(int f=0;f<32;f++)
    {
        game_time+=1.0f/60;vpt::update_rigs(1.0f/60);game_post(1.0f/60);
        rl::begin_drawing();vpt::draw_scene(cam,{0,0,1280,720});rl::end_drawing();
    }
    vpt::export_frame(path);
}
fn void layer_checks()
{
    assert(gen_layer==0&&gen_active,"Start this test with surface:SEED.");
    uint seed=gen_seed;assert(vpt::lighting.sun_power>0&&vpt::terrain_hidden);
    assert(count_kind(SCAVENGER)>0&&count_kind(STALKER)>0&&count_kind(NEST)>=2,"Surface wildlife plus one localized alien den must exist.");
    assert(kind[check_boss()]==CRAWLER&&surface_cave_at(vpt::rigs[check_boss()].x,vpt::rigs[check_boss()].z)>=0,"The surface boss is the alien crawler inside one side cave.");
    for(int stop=0;stop<SURFACE_STOPS-1;stop++)
    {
        Vec a=surface_stop(stop,seed);Vec b=surface_stop(stop+1,seed);
        for(int k=0;k<=80;k++)
        {
            Vec p=a+(b-a)*((float)k/80);
            assert(!vpt::blocked(p[0],p[2],0.1f,0.45f),"Surface expedition trail must stay connected and walkable.");
        }
    }
    aim_geometry_check();
    int original=vpt::instance_count;int concealed=game_item_count;game_stop();
    assert(vpt::save_scene("dev/output/surface-roundtrip.vptscene.json"));
    assert(vpt::load_scene("dev/output/surface-roundtrip.vptscene.json"));
    assert(gen_layer==0&&gen_seed==seed&&vpt::instance_count==original,"Surface save/load must retain biome and rebake detail exactly once.");
    assert(game_item_count==concealed);for(int k=0;k<concealed;k++)assert(game_items[k].contained,"Crate contents must remain concealed after save/load.");
    int robot= -1;for(int r=0;r<vpt::rig_count;r++)if(is_player_rig(r))robot=r;
    assert(robot>=0);vpt::begin_undo();vpt::controlled_rig=robot;game_start();
    int bound=0;for(int i=0;i<vpt::instance_count;i++)if(prop_loot[i]>=0)bound++;
    assert(bound==concealed&&pickup_count==0,"Reloaded crate loot must bind once, without spawning loose duplicates.");
    god=true;auto_aim=true;skill[SK_MULTI]=2;skill[SK_SCANNER]=1;skill_points=2;xp=7;level=4;player_hp=63;keys=2;
    assert(!layer_clear&&portal_exists&&!portal_armed);
    // Distinct surface behavior: a scavenger retreats; an elder braces then commits to a dodgeable lane.
    int elder= -1;for(int r=0;r<vpt::rig_count;r++)if(kind[r]==STALKER) { elder=r;break; }assert(elder>=0);vpt::Rig* hunter=&vpt::rigs[elder];Vec hunt_pos={hunter.x,hunter.y,hunter.z};
    bool braced=false;
    for(int a=0;a<4&&!braced;a++)
    {
        float angle=(float)a*1.5708f;Vec target=hunt_pos+(Vec){math::cos(angle)*3,0,math::sin(angle)*3};
        aware[elder]=true;brood[elder].leap=0;update_surface_creature(elder,0.05f,target,true,false);braced=fuse[elder]>0;
        if(braced)
        {
            assert(!hunter.hunting,"Stalkers must telegraph before charging.");update_surface_creature(elder,1,target,true,false);
            assert(rush[elder]>0);Vec committed=brood[elder].perch;
            update_surface_creature(elder,0.05f,target+(Vec){3,0,0},true,false);
            assert(vpt::dot(hunter.hunt_target-committed,hunter.hunt_target-committed)<0.001f,"Stalker charges must not home after committing.");
        }
    }
    assert(braced);aware[elder]=false;fuse[elder]= -1;rush[elder]=0;hunter.hunting=false;
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SCAVENGER)
    {
        vpt::Rig* bug=&vpt::rigs[r];Vec pos={bug.x,bug.y,bug.z};
        for(int a=0;a<4&&!aware[r];a++)
        { float angle=(float)a*1.5708f;update_surface_creature(r,0.34f,pos+(Vec){math::cos(angle),0,math::sin(angle)},true,false); }
        assert(aware[r]&&brood[r].alarm&&(brood[r].scatter>0)==(brood[r].temperament<=0.45f),"A disturbed scavenger reacts at once: bold ones fight, shy ones bolt first.");break;
    }
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SCAVENGER) { kill_rig(r,{0,0,1});break; }
    assert(!layer_clear,"Non-boss kills must not open the rift.");
    int boss=check_boss();assert(boss>=0);kill_rig(boss,{0,0,1});assert(layer_clear&&!layer_pending);
    vpt::Rig* me=&vpt::rigs[player];me.x=portal_base[0]+4;me.z=portal_base[2];me.y=portal_base[1];
    progression_update(3);assert(portal_armed&&!layer_pending,"Boss death opens a portal, never automatically descends.");
    capture_rift("dev/output/rift-surface.png");
    assert(vpt::dyn_count>100,"Rift needs actual animated world geometry, not only a HUD message.");
    me=&vpt::rigs[player];me.x=portal_base[0];me.z=portal_base[2];me.y=portal_base[1];
    progression_update(0.05f);assert(portal_fade>0);progression_update(1);assert(layer_pending);
    SkillState before=skills_save();   // the boss kill above added XP: compare with the state at the rift
    apply_layer_transition();
    assert(gen_layer== -1&&game_on&&!layer_clear&&portal_exists,"Surface portal must generate and possess the cave layer.");
    assert(player_hp==63&&skill[SK_MULTI]==2&&skill[SK_SCANNER]==1&&skill_points==before.points&&xp==before.xp&&level==before.level&&level>4&&keys==2&&auto_aim&&god,"Descent must carry hull, upgrades, keys and aim settings.");
    assert(vpt::lighting.sun_power==0&&vpt::terrain_hidden&&count_kind(NEST)>0,"Caves must keep their dark, roofed alien identity.");
    aim_geometry_check();
    boss=check_boss();assert(boss>=0);kill_rig(boss,{0,0,1});
    me=&vpt::rigs[player];me.x=portal_base[0]+4;me.z=portal_base[2];me.y=portal_base[1];progression_update(3);
    capture_rift("dev/output/rift-cave.png");
    me=&vpt::rigs[player];me.x=portal_base[0];me.z=portal_base[2];me.y=portal_base[1];progression_update(0.05f);progression_update(1);
    assert(coming_soon&&!layer_pending&&gen_layer== -1,"Layer -2 must be an explicit coming-soon endpoint, not a missing-map transition.");
    game_restart();
    assert(game_on&&gen_layer==0&&player_hp==100&&skill[SK_MULTI]==0&&level==1&&!coming_soon,"R must start a fresh surface expedition from the endpoint.");
    io::printn("VPT LAYER CHECKS PASSED: surface identity/trail, save/load, wildlife AI, boss gate, animated portal, carried equipment, 0 -> -1 -> -2 coming soon, restart");
}
