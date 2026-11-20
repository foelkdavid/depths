module depths;
import std::math;
import std::io;
import raylib6::rl;
import vpt;

bool test_habitat;
fn void habitat_capture(rl::RLCamera3D cam,ZString path,bool grid=false)
{
    vpt::show_grid=grid;vpt::lighting.quality=1;
    for(int f=0;f<24;f++)
    {
        game_time+=1.0f/60;vpt::update_rigs(1.0f/60);game_post(1.0f/60);
        rl::begin_drawing();vpt::draw_scene(cam,{0,0,1280,720});rl::end_drawing();
    }
    vpt::export_frame(path);
}
bool bench_no_extras;
// In-game cost of the new dyn objects at 1280x720 (play camera): motes + spores + weapon vs none, and a shotgun burst.
fn double game_frames_ms(rl::RLCamera3D cam,int n,bool shells)
{
    vpt::Rig* me=&vpt::rigs[player];Vec target={me.x,me.y,me.z+8};
    double start=rl::get_time();
    for(int f=0;f<n;f++)
    {
        if(shells&&f%20==0) { bolt_count=0;fire_shell(me,target); }
        for(int b=0;b<bolt_count;) { bolts[b].p+=bolts[b].v*(1.0f/60);bolts[b].life-=1.0f/60;if(bolts[b].life<=0) { bolts[b]=bolts[--bolt_count];continue; }b++; }   // fly like in game
        game_time+=1.0f/60;weapon_update(1.0f/60);vpt::update_rigs(1.0f/60);
        if(bench_no_extras) { vpt::dyn_begin();vpt::dyn_end(); } else { game_post(1.0f/60); }
        rl::begin_drawing();vpt::draw_scene(cam,{0,0,1280,720});rl::end_drawing();
    }
    rl::RLVector4* sync=vpt::read_pixels(vpt::output_texture());rl::mem_free(sync);
    return (rl::get_time()-start)*1000/(double)n;
}
fn void atmosphere_bench()
{
    vpt::Rig* me=&vpt::rigs[player];Vec at={me.x,me.y+0.4f,me.z};float d=15.3f;vpt::lighting.quality=1;vpt::show_grid=false;
    rl::RLCamera3D cam={.position=at+(Vec){math::sin(0.68f)*math::cos(1.02f)*d,math::sin(1.02f)*d,math::cos(0.68f)*math::cos(1.02f)*d},.target=at,.up={0,1,0},.fovy=32.78f,.projection=rl::RLCameraProjection.PERSPECTIVE};
    bench_no_extras=true;(void)game_frames_ms(cam,20,false);double base=game_frames_ms(cam,90,false);
    bench_no_extras=false;(void)game_frames_ms(cam,20,false);double extra=game_frames_ms(cam,90,false);double shells=game_frames_ms(cam,90,true);bolt_count=0;
    io::printfn("VPT GAME VIEW BENCH: top-down 1280x720: bare %.2f ms, +weapon/motes/spores %.2f ms, +shotgun bursts %.2f ms",base,extra,shells);
}
fn void weapon_frames(int n,Vec target)
{
    vpt::Rig* me=&vpt::rigs[player];
    for(int f=0;f<n;f++) { game_time+=1.0f/60;me.has_look_point=true;me.look_point=target;weapon_update(1.0f/60);vpt::update_rigs(1.0f/60);game_post(1.0f/60); }
}
// Weapons: attachments exist, swapping folds/unfolds, shots leave the real muzzle, shotgun pellet counts.
// Hit feedback: flash on the struck creature, health bar, one merged number per shell, hit marker (HUD screenshot).
fn void hit_feedback_check()
{
    vpt::Rig* me=&vpt::rigs[player];int best= -1;
    for(int r=0;r<vpt::rig_count&&best<0;r++)if(kind[r]==SCAVENGER||kind[r]==STALKER&&vpt::rigs[r].scale<1.3f)best=r;
    for(int r=0;r<vpt::rig_count&&best<0;r++)if(kind[r]==CRAWLER||kind[r]==SKITTER)best=r;
    if(best<0) { io::printn("VPT HIT FEEDBACK: no creature to test");return; }
    vpt::Rig* e=&vpt::rigs[best];float hp0=hp[best];if(hp0<3) { hp[best]=hp_max[best]=8;hp0=8; }
    // bring it into the open beside the robot (the scene is restored after the test)
    Vec fwd=vpt::rig_dir(me,{0,0,1});e.x=me.x+fwd[0]*3;e.z=me.z+fwd[2]*3;e.y=me.y;e.oriented=false;e.hunting=false;e.held=true;e.airborne=false;e.flying=false;
    for(int f=0;f<10;f++)vpt::update_rigs(1.0f/60);
    Vec c={e.x,e.y+0.3f*e.scale,e.z};Vec d=nrm((Vec){1,0,0.3f});
    for(int k=0;k<3;k++)hit_rig(best,c,d,0.5f,true);
    assert(vpt::rig_hit_flash[best]>0.5f&&bar_t[best]>0&&marker_t>0,"A hit must flash the creature, show its bar and the marker.");
    int live=0;float sum=0;foreach(t:hit_texts)if(t.t>0&&t.rig==best) { live++;sum+=t.v; }
    assert(live==1&&math::abs(sum-1.5f)<0.01f,"Pellets of one shell merge into one number.");
    Vec side=vpt::rig_dir(me,{1,0,0});
    rl::RLCamera3D cam={.position=c+side*2.6f-fwd*1.2f+(Vec){0,1.5f,0},.target=c,.up={0,1,0},.fovy=45,.projection=rl::RLCameraProjection.PERSPECTIVE};
    bool tp=third_person;third_person=false;
    for(int f=0;f<20;f++)
    {
        vpt::rig_hit_flash[best]=1;game_time+=1.0f/60;vpt::update_rigs(1.0f/60);game_post(1.0f/60);
        rl::begin_drawing();vpt::draw_scene(cam,{0,0,1280,720});draw_game_hud({0,0,1280,720},cam);rl::end_drawing();
    }
    rl::take_screenshot("dev/output/hit-feedback-hud.png");third_person=tp;
    vpt::rig_hit_flash[best]=0;habitat_capture(cam,"dev/output/hit-flash-off.png");
    vpt::rig_hit_flash[best]=1;habitat_capture(cam,"dev/output/hit-flash-on.png");
    vpt::rig_hit_flash[best]=0;hit_texts={};marker_t=0;bar_t[best]=0;hp[best]=hp0;e.held=false;
    io::printn("VPT HIT FEEDBACK CHECKS PASSED: flash, health bar, merged numbers, hit marker");
}
// Layer-0 ground must crater wherever a shot lands on it (flats, hills, den floors), at the VISIBLE surface.
fn void surface_crater_check()
{
    int tried=0;int carved=0;int off=0;float worst=0;
    for(int i=0;i<160;i++)
    {
        float x=vpt::hash2(i,7,881)*100-50;float z=vpt::hash2(i,13,882)*100-50;float a=vpt::hash2(i,3,883)*6.283f;
        float h=surface_height(x,z,gen_seed);Vec at={x,h,z};Vec from=at+(Vec){math::cos(a)*5,2.2f,math::sin(a)*5};
        vpt::Pick hit=vpt::shot_pick({from,nrm(at-from)},player);
        if(!hit.hit||hit.rig>=0)continue;
        if(hit.instance>=0&&!vpt::assets[vpt::instances[hit.instance].asset].generated)continue;   // props have their own carving
        if(hit.instance>=0&&vpt::assets[vpt::instances[hit.instance].asset].roof)continue;
        tried++;Vec p=hit.point;float gh=surface_height(p[0],p[2],gen_seed);
        if(surface_cave_at(p[0],p[2])<0&&gh<1.5f) { float e=math::abs(p[1]-gh);worst=math::max(worst,e);if(e>0.3f)off++; }
        int before=blast_hits;blast_terrain(p+nrm(at-from)*0.04f,0.14f,0.25f);if(blast_hits>before)carved++;
        if(blast_hits==before&&off<4)io::printfn("  no crater at %.1f %.1f %.1f (ground %.2f, inst %d)",p[0],p[1],p[2],gh,hit.instance);
    }
    io::printfn("VPT SURFACE CRATERS: %d/%d shots carved the ground, %d off the visible surface (worst %.2f m)",carved,tried,off,worst);
    assert(tried>100&&carved>=tried*95/100,"Shots must crater layer-0 ground everywhere.");
    assert(off<=tried/50,"Shots must hit the visible fine ground, not the hidden 1 m collision terrain.");
    // rocket-sized craters for the eye: flat ground in front of the robot and the nearest slope
    vpt::Rig* me=&vpt::rigs[player];Vec fwd=vpt::rig_dir(me,{0,0,1});Vec g={me.x+fwd[0]*5,0,me.z+fwd[2]*5};g[1]=surface_height(g[0],g[2],gen_seed);
    blast_terrain(g,0.75f,1.0f);blast_terrain(g+(Vec){1.3f,0,0.4f},0.5f,1.0f);
    for(float k=1;k<12;k+=0.25f) { Vec q={g[0]+fwd[0]*k,0,g[2]+fwd[2]*k};float hq=surface_height(q[0],q[2],gen_seed);if(hq>g[1]+1.2f) { q[1]=hq-0.6f;q-=fwd*0.5f;blast_terrain(q,0.7f,1.0f);break; } }
    rl::RLCamera3D cam={.position=g-fwd*2.5f+(Vec){1.5f,3.2f,0},.target=g+fwd*1.5f,.up={0,1,0},.fovy=55,.projection=rl::RLCameraProjection.PERSPECTIVE};
    atmosphere_off=true;habitat_capture(cam,"dev/output/surface-crater.png");atmosphere_off=false;
    { vpt::Lighting saved=vpt::lighting;vpt::lighting=vpt::DEFAULT_LIGHTING;habitat_capture(cam,"dev/output/surface-crater-day.png");vpt::lighting=saved; }
}
// HUD/menu into an offscreen 1280x720 target (screen readback is unreliable headless), over a dim backdrop.
fn void hud_capture(rl::RLCamera3D cam,ZString path)
{
    rl::RLRenderTexture2D rt=rl::load_render_texture(1280,720);
    for(int f=0;f<4;f++)
    {
        rl::begin_drawing();rl::begin_texture_mode(rt);rl::clear_background({38,34,30,255});
        rl::draw_rectangle_gradient_v(0,0,1280,720,{58,50,40,255},{20,18,16,255});draw_game_hud({0,0,1280,720},cam);
        rl::end_texture_mode();rl::end_drawing();
    }
    rl::RLImage img=rl::load_image_from_texture(rt.texture);rl::image_flip_vertical(&img);(void)rl::export_image(img,path);rl::unload_image(img);rl::unload_render_texture(rt);
}
// Skill tree: XP -> levels -> points, prerequisites, crate perks only from unlockable nodes, station respec,
// multi-gun muzzles; captures the fully upgraded robot and the tree menu.
fn void skills_check()
{
    skills_reset();assert(level==1&&skill_points==0);
    gain_xp(xp_to_next(1));assert(level==2&&skill_points==1,"A level gives a skill point.");
    assert(!skill_install(SK_DASH,false),"Dash needs Servo 2 first.");
    assert(skill_install(SK_SERVO,false)&&skill_points==0&&!skill_install(SK_SERVO,false),"Installing spends points.");
    for(int k=0;k<40;k++) { int s=random_available_skill();if(s<0)break;assert(skill_available(s),"Perks only roll unlockable skills.");skill_install(s,true); }
    for(int k=0;k<SK_COUNT;k++)assert(skill[k]==SKILLS[k].max,"Free perks eventually fill the whole tree.");
    int total=0;for(int k=0;k<SK_COUNT;k++)total+=skill[k];skills_respec();assert(skill_points==total+0&&skill[SK_SERVO]==0,"Respec refunds every level.");
    // multi-gun: three guns, three muzzles, three bolts per trigger
    skills_reset();for(int k=0;k<SK_COUNT;k++)skill[k]=SKILLS[k].max;
    vpt::Rig* me=&vpt::rigs[player];Vec fwd=vpt::rig_dir(me,{0,0,1});Vec right=vpt::rig_dir(me,{1,0,0});Vec body={me.x,me.y+0.55f,me.z};
    weapon_select(W_MG);weapon_frames(60,body+fwd*8);
    Vec m0=weapon_muzzle(0,0);Vec m2=weapon_muzzle(0,2);assert(math::abs(vpt::dot(m2-m0,right))>0.45f,"Side guns sit apart on the yoke.");
    int before=bolt_count;fire_shot(me,body+fwd*8,false);assert(bolt_count-before==3,"Three guns fire three bolts.");bolt_count=0;
    // captures: fully upgraded robot, both mounts
    for(int f=0;f<30;f++) { game_time+=1.0f/60;skills_update(1.0f/60);weapon_frames(1,body+fwd*8); }
    rl::RLCamera3D c1={.position=body+fwd*2.0f+right*1.4f+(Vec){0,0.9f,0},.target=body+(Vec){0,0.1f,0},.up={0,1,0},.fovy=50,.projection=rl::RLCameraProjection.PERSPECTIVE};
    rl::RLCamera3D c2={.position=body-fwd*1.9f-right*1.3f+(Vec){0,1.1f,0},.target=body+(Vec){0,0.1f,0},.up={0,1,0},.fovy=50,.projection=rl::RLCameraProjection.PERSPECTIVE};
    atmosphere_off=true;
    { vpt::Lighting saved=vpt::lighting;vpt::lighting=vpt::DEFAULT_LIGHTING;habitat_capture(c1,"dev/output/skills-robot-front.png");habitat_capture(c2,"dev/output/skills-robot-back.png");
      rl::RLCamera3D c3={.position=body+right*2.4f+fwd*0.3f+(Vec){0,0.5f,0},.target=body,.up={0,1,0},.fovy=45,.projection=rl::RLCameraProjection.PERSPECTIVE};habitat_capture(c3,"dev/output/skills-robot-side.png");vpt::lighting=saved; }
    habitat_capture(c1,"dev/output/skills-robot-front-night.png");
    weapon_toggle_mount();weapon_frames(70,body+fwd*8);
    { vpt::Lighting saved=vpt::lighting;vpt::lighting=vpt::DEFAULT_LIGHTING;habitat_capture(c1,"dev/output/skills-robot-under.png");vpt::lighting=saved; }
    weapon_toggle_mount();weapon_frames(70,body+fwd*8);atmosphere_off=false;
    // the tree menu (partially skilled, points to spend)
    skills_reset();skill[SK_SERVO]=2;skill[SK_OVERCLOCK]=1;skill[SK_MULTI]=1;skill[SK_REGEN]=1;skill_points=3;level=6;xp=40;skills_open=true;
    hud_capture(c1,"dev/output/skills-menu.png");skills_open=false;
    hud_capture(c1,"dev/output/skills-hud.png");
    skills_reset();weapon_frames(40,body+fwd*8);
    io::printn("VPT SKILL CHECKS PASSED: XP/levels, prerequisites, perks from unlockable nodes, respec, multi-gun muzzles");
}
fn void weapon_check()
{
    assert(weapons_ready,"Weapon attachments must load.");int multi_was=skill[SK_MULTI];skill[SK_MULTI]=0;
    vpt::Rig* me=&vpt::rigs[player];Vec fwd=vpt::rig_dir(me,{0,0,1});Vec right=vpt::rig_dir(me,{1,0,0});
    Vec body={me.x,me.y+0.55f,me.z};Vec target=body+fwd*8;
    rl::RLCamera3D cam={.position=body+fwd*1.25f+right*0.85f+(Vec){0,0.32f,0},.target=body+fwd*0.25f,.up={0,1,0},.fovy=48,.projection=rl::RLCameraProjection.PERSPECTIVE};
    const ZString[3] SHOTS={"dev/output/weapon-mg.png","dev/output/weapon-rocket.png","dev/output/weapon-shotgun.png"};
    for(int w=0;w<WEAPON_COUNT;w++)
    {
        weapon_select(w);
        if(w>0)
        {
            assert(swap_stage==1,"Selecting another weapon must fold the current one first.");
            weapon_frames(9,target);Vec low=weapon_muzzle(0);Vec hinge_w;vpt::Quat q;float sc;Vec sh;Vec pos;assert(body_frame(&pos,&q,&sc,&sh));hinge_w=body_point(pos,q,sc,sh,w_hinge);
            hinge_w=body_point(pos,q,sc,sh,mount_hinge());assert(weapon_mount==MOUNT_TOP?low[1]>hinge_w[1]:low[1]<hinge_w[1],"Folding: down under the nose / up and back on the deck mount.");
            if(w==1)habitat_capture(cam,"dev/output/weapon-swap.png",true);
        }
        weapon_frames(40,target);
        assert(weapon==w&&swap_stage==0&&weapon_ready(),"The new weapon must finish swinging up.");
        Vec m=weapon_muzzle(0);Vec off=vpt::qrot(vpt::qconj(vpt::rig_part_q[first_part(player)]),m-body);
        assert(vpt::dot(m-body,fwd)>0.3f,"The muzzle must sit at the front of the robot.");
        habitat_capture(cam,SHOTS[w],true);
        if(w!=W_ROCKET)
        {
            int before=bolt_count;Vec at=muzzle((barrel+1)%weapon_muzzles());
            if(w==W_SHOTGUN) { fire_shell(me,target); } else { fire_shot(me,target,false); }
            assert(bolt_count>before,"Firing must spawn shots.");
            Vec d=bolts[before].p-at;assert(vpt::dot(d,d)<0.01f,"Shots must leave the actual muzzle.");
            if(w==W_SHOTGUN) { assert(bolt_count-before==9,"A shell is nine pellets.");skill[SK_MULTI]=2;int b2=bolt_count;fire_shell(me,target);assert(bolt_count-b2==27,"Three guns fire three shells.");skill[SK_MULTI]=0; }
            bolt_count=0;weapon_frames(30,target);
        }
    }
    weapon_select(W_MG);weapon_frames(40,target);
    // F3: fold away, change mount, swing up there; muzzle height follows the mount.
    int mount0=weapon_mount;float y0=weapon_muzzle(0)[1];weapon_toggle_mount();weapon_frames(60,target);
    assert(weapon_mount==1-mount0&&swap_stage==0&&weapon==W_MG,"F3 must move the weapon to the other mount.");
    float y1=weapon_muzzle(0)[1];assert(mount0==MOUNT_TOP?y1<y0-0.1f:y1>y0+0.1f,"The muzzle must move with the mount.");
    habitat_capture(cam,weapon_mount==MOUNT_TOP?"dev/output/weapon-mount-top.png":"dev/output/weapon-mount-under.png",true);
    weapon_toggle_mount();weapon_frames(60,target);assert(weapon_mount==mount0);
    habitat_capture(cam,weapon_mount==MOUNT_TOP?"dev/output/weapon-mount-top.png":"dev/output/weapon-mount-under.png",true);
    // a rocket in flight (voxel round) for the eye
    weapon_select(W_ROCKET);weapon_frames(40,target);bolt_count=0;fire_shot(me,target,true);
    for(int f=0;f<7;f++) { Bolt* rb=&bolts[0];rb.prev=rb.p;rb.p+=rb.v*(1.0f/60);weapon_frames(1,target); }
    rl::RLCamera3D side={.position=bolts[0].p+right*1.4f+(Vec){0,0.35f,0},.target=bolts[0].p,.up={0,1,0},.fovy=40,.projection=rl::RLCameraProjection.PERSPECTIVE};
    habitat_capture(side,"dev/output/rocket-flight.png",true);
    bolt_count=0;fire_shell(me,target);for(int f=0;f<3;f++) { for(int b=0;b<bolt_count;b++)bolts[b].p+=bolts[b].v*(1.0f/60); }
    rl::RLCamera3D shellcam={.position=body+right*2.2f+fwd*1.5f+(Vec){0,1.0f,0},.target=body+fwd*3.5f,.up={0,1,0},.fovy=55,.projection=rl::RLCameraProjection.PERSPECTIVE};
    atmosphere_off=true;habitat_capture(shellcam,"dev/output/shotgun-shell.png",true);atmosphere_off=false;bolt_count=0;
    weapon_select(W_MG);weapon_frames(40,target);skill[SK_MULTI]=multi_was;
    io::printn("VPT WEAPON CHECKS PASSED: 3 folding weapons, real muzzles, 9/27 pellets, multi-gun shells");
}
// Placed props break voxel by voxel: a bullet takes a bite (the prop stays), cutting through the base drops the rest.
fn void prop_destruction_check()
{
    int placed=0;int carvable=0;int tall= -1;float tallest=0;
    for(int i=0;i<vpt::instance_count;i++)
    {
        vpt::Asset* a=&vpt::assets[vpt::instances[i].asset];if(a.generated||vpt::hidden[i])continue;placed++;
        if(!a.prop_clone)continue;carvable++;float h=(float)a.dy*a.size*vpt::instances[i].scale;
        if(h>tallest&&a.dy-a.foot>12) { tallest=h;tall=i; }
    }
    assert(tall>=0,"The surface needs a tall carvable prop.");
    vpt::Instance it=vpt::instances[tall];vpt::Asset* a=&vpt::assets[it.asset];int full=a.occupied;prop_full[tall]=full;
    // one bullet bite into the middle of the prop
    Vec mid=vpt::prop_voxel_world(it,a,a.dx/2,(a.foot+a.dy)/2,a.dz/2);
    blast_terrain(mid,0.2f,0.15f,true);settle_props();
    assert(!vpt::hidden[tall]&&a.occupied<full&&a.occupied>full/2,"A bullet must remove voxels, not pop the whole prop.");
    for(int k=0;k<5;k++) { Vec q=vpt::prop_voxel_world(it,a,a.dx/2+k-2,(a.foot+a.dy)/2+(k%2)*3,0);blast_terrain(q,0.2f,0.15f,true); }
    settle_props();
    float view_h=(float)a.dy*a.size*it.scale;
    rl::RLCamera3D close={.position=mid+(Vec){view_h*0.9f,view_h*0.25f,-view_h*1.2f},.target=mid,.up={0,1,0},.fovy=50,.projection=rl::RLCameraProjection.PERSPECTIVE};
    habitat_capture(close,"dev/output/prop-carved.png");
    // saw through the footing: the rest has nothing to stand on and falls as debris
    int debris=stat_debris;float footing=(float)(a.foot+1)*a.size*it.scale;
    for(int z=0;z<a.dz;z+=2)for(int x=0;x<a.dx;x+=2)
    {
        Vec p=vpt::prop_voxel_world(it,a,x,a.foot,z);p[1]=it.y+(a.origin[1]*it.scale)+footing;blast_terrain(p,math::max(0.12f,a.size*it.scale*2.5f),0,true);
    }
    settle_props();
    assert(vpt::hidden[tall]||a.occupied<full/10,"Cutting a prop's base must topple what stood on it.");
    assert(stat_debris>debris,"Toppled voxels must fall as debris.");
    for(int f=0;f<20;f++) { game_time+=1.0f/60;game_update(1.0f/60,{},false,false); }
    habitat_capture(close,"dev/output/prop-toppled.png");
    io::printfn("VPT PROP DESTRUCTION CHECKS PASSED: %d/%d placed props carvable voxel by voxel, %.1f m prop toppled",carvable,placed,tallest);
}
// L-1 boss charge in V (third person): frame cost and camera behaviour while the boss rushes the robot.
bool test_boss_v;
fn void boss_v_bench()
{
    int boss= -1;for(int r=0;r<vpt::rig_count;r++)if(is_layer_boss(r))boss=r;
    if(boss<0||player<0) { io::printn("VPT BOSS V: no boss");return; }
    god=true;vpt::Rig* b=&vpt::rigs[boss];vpt::Rig* me=&vpt::rigs[player];
    // robot 8 m from the boss along the first open direction
    for(int k=0;k<16;k++) { float a=(float)k*0.3927f;float x=b.x+math::sin(a)*8;float z=b.z+math::cos(a)*8;if(!vpt::blocked(x,z,b.y,0.6f)&&!vpt::blocked((x+b.x)/2,(z+b.z)/2,b.y,0.6f)) { me.x=x;me.z=z;me.y=b.y;break; } }
    aware[boss]=true;third_person=true;tp_snap=true;tp_yaw=math::atan2(b.x-me.x,b.z-me.z);tp_pitch=0.25f;
    double worst=0;double total=0;int n=0;float min_arm=99;float max_jump=0;rl::RLVector3 last={};float dist_min=99;
    for(int f=0;f<300;f++)
    {
        double t0=rl::get_time();float dt=1.0f/60;
        if(boss<vpt::rig_count)tp_yaw=math::atan2(vpt::rigs[boss].x-me.x,vpt::rigs[boss].z-me.z);   // the player keeps the boss in view
        set_roof_visible(true);rl::RLCamera3D cam=tp_camera(*me,dt);if(f>0){ rl::RLVector3 j=cam.position-last;max_jump=math::max(max_jump,math::sqrt(vpt::dot(j,j))); }last=cam.position;min_arm=math::min(min_arm,tp_arm);
        game_update(dt,tp_aim_ray(),true,false);apply_layer_transition();vpt::update_rigs(dt);game_post(dt);
        vpt::lighting.quality=1;rl::begin_drawing();vpt::draw_scene(cam,{0,0,1280,720});rl::end_drawing();
        rl::RLVector4* sync=vpt::read_pixels(vpt::output_texture());rl::mem_free(sync);
        double t=rl::get_time()-t0;if(f>20) { worst=math::max(worst,t);total+=t;n++; }
        if(boss<vpt::rig_count) { float dx=vpt::rigs[boss].x-me.x;float dz=vpt::rigs[boss].z-me.z;dist_min=math::min(dist_min,math::sqrt(dx*dx+dz*dz)); }
        if(f==150||f==60)vpt::export_frame(f==60?"dev/output/boss-v-60.png":"dev/output/boss-v-150.png");
    }
    io::printfn("VPT BOSS V BENCH: avg %.2f ms worst %.2f ms, closest boss %.2f m, min arm %.2f m, max camera jump %.2f m/frame, hull %.0f",total*1000/n,worst*1000,dist_min,min_arm,max_jump,player_hp);
}
fn void habitat_flutter_check()
{
    int r= -1;for(int k=0;k<vpt::rig_count;k++)if(kind[k]==FLUTTER) { r=k;break; }
    assert(r>=0,"Habitat fixture needs a flutter.");god=true;
    vpt::Rig* e=&vpt::rigs[r];Vec home=flutter_home_air(r);e.x=home[0];e.y=home[1];e.z=home[2];e.oriented=false;e.flying=true;e.velocity={};
    float height=e.y;
    for(int retry=0;retry<100;retry++)flutter_destination(r,{100,1000,100});
    assert(math::abs(e.y-height)<0.001f,"Airborne replanning must not ratchet the flutter up through its roof.");
    for(int f=0;f<1200;f++)
    {
        update_flutter(r,1.0f/60,{1000,1000,1000},true,false);vpt::update_rigs(1.0f/60);
        if(e.flying)assert(vpt::flight_in_bounds({e.x,e.y,e.z}),"Flutter flight must stay in playable air.");
        assert(math::abs(e.x)<(float)vpt::world_size*0.5f&&math::abs(e.z)<(float)vpt::world_size*0.5f&&e.y<12,"Flutter must not escape the world or climb above the cave.");
    }
    e.x=1000;e.y=300;e.z=1000;e.flying=true;e.oriented=false;
    update_flutter(r,1.0f/60,{1000,1000,1000},true,false);
    assert(vpt::flight_in_bounds({e.x,e.y,e.z}),"An already-escaped flutter must recover to its roost.");
    io::printn("VPT FLUTTER BOUNDS CHECKS PASSED: 100 replans, 20 s flight, escaped-state recovery");
}
// Layer-0 wildlife: lively idle (moving a good share of the time) and instant reactions to a hit, the robot
// stepping close and a shot landing next to them.
fn void surface_frames(int n)
{
    rl::RLRay ray={{0,50,0},{0,-1,0}};
    for(int f=0;f<n;f++) { game_update(1.0f/60,ray,false,false);vpt::update_rigs(1.0f/60);game_post(1.0f/60); }
}
fn void surface_reaction_check()
{
    god=true;vpt::Rig* me=&vpt::rigs[player];Vec spawn={me.x,me.y,me.z};
    me.x=60;me.z=60;   // far corner: everyone idles
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SCAVENGER||kind[r]==STALKER) { aware[r]=false;brood[r].alarm=false;brood[r].memory=0;brood[r].scatter=0; }
    float moving=0;float speed=0;int samples=0;float turn=0;float[vpt::MAX_RIGS] yaw0;
    for(int r=0;r<vpt::rig_count;r++)yaw0[r]=vpt::rigs[r].yaw;
    for(int f=0;f<600;f++)
    {
        surface_frames(1);
        for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SCAVENGER&&!aware[r])
        {
            Vec v=vpt::rigs[r].velocity;float sp=math::sqrt(v[0]*v[0]+v[2]*v[2]);speed+=sp;if(sp>0.15f)moving+=1;samples++;
            float dy=vpt::rigs[r].yaw-yaw0[r];while(dy>180)dy-=360;while(dy< -180)dy+=360;turn+=math::abs(dy);yaw0[r]=vpt::rigs[r].yaw;
        }
    }
    float moving_share=samples?moving/(float)samples:0;
    io::printfn("VPT SURFACE IDLE: scavengers move %.0f%% of the time, mean speed %.2f m/s, turning %.0f deg/s",moving_share*100,samples?speed/(float)samples:0,samples?turn/(float)samples*60:0);
    assert(moving_share>0.35f,"Idle scavengers must be lively (moving a good share of the time).");
    // 1. hit -> instant reaction
    int sc= -1;int st= -1;for(int r=0;r<vpt::rig_count;r++) { if(kind[r]==SCAVENGER&&sc<0&&!aware[r])sc=r;if(kind[r]==STALKER&&st<0&&!is_layer_boss(r))st=r; }
    assert(sc>=0,"Surface fixture needs a scavenger.");
    vpt::Rig* e=&vpt::rigs[sc];me.x=e.x+7;me.z=e.z;me.y=e.y;
    hit_rig(sc,{e.x,e.y+0.2f,e.z},{-1,0,0},0.1f);
    assert(aware[sc]&&brood[sc].alarm,"A hit scavenger must react at once.");
    surface_frames(20);assert(vpt::rigs[sc].hunting||brood[sc].scatter>0,"A hit scavenger must rush the robot (or bolt) within 1/3 s.");
    // 2. robot steps close -> instant reaction (fresh, unaware creature)
    int sc2= -1;for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SCAVENGER&&!aware[r]&&r!=sc) { Vec dv={vpt::rigs[r].x-e.x,0,vpt::rigs[r].z-e.z};if(vpt::dot(dv,dv)>400) { sc2=r;break; } }
    if(sc2>=0)
    {
        vpt::Rig* e2=&vpt::rigs[sc2];me.x=e2.x+1.5f;me.z=e2.z+1.0f;me.y=e2.y;surface_frames(3);
        assert(aware[sc2],"A scavenger must notice the robot right next to it immediately.");
    }
    // 3. stalker: hit -> rears and braces a charge right away
    if(st>=0)
    {
        vpt::Rig* s2=&vpt::rigs[st];me.x=s2.x+6;me.z=s2.z;me.y=s2.y;rush[st]=0;fuse[st]= -1;
        hit_rig(st,{s2.x,s2.y+0.5f,s2.z},{-1,0,0},0.1f);surface_frames(30);
        assert(fuse[st]>=0||rush[st]>0||!brood_sees(s2,{me.x,me.y+0.6f,me.z}),"A hit stalker must brace/charge within half a second (when it can see the robot).");
    }
    me.x=spawn[0];me.y=spawn[1];me.z=spawn[2];
    io::printn("VPT SURFACE REACTION CHECKS PASSED: lively idle, instant hit / proximity reactions, stalker brace");
}
fn void habitat_surface_check()
{
    assert(gen_layer==0&&vpt::sky_map.id>0&&vpt::sky_map_on);
    god=true;arrival_time=0;Vec spawn={vpt::rigs[player].x,vpt::rigs[player].y,vpt::rigs[player].z};
    int grouped=0;
    for(int i=0;i<vpt::instance_count;i++)if(vpt::assets[vpt::instances[i].asset].roof_group>0)grouped++;
    assert(grouped>30,"Side caves must have real roof geometry.");
    for(int i=0;i<3;i++)
    {
        SurfaceCave c=surface_caves[i];Vec from=surface_stop(2+i*2,gen_seed);
        for(int s=0;s<=60;s++) { Vec p=from+(c.center-from)*((float)s/60);assert(!vpt::blocked(p[0],p[2],0.12f,0.45f),"Side cave entrance must be walkable from the trail."); }
        // The mouth must be VISIBLY open: no terrain skin, lintel or prop between the trail and the chamber.
        Vec flat=c.center-from;flat[1]=0;float reach=math::sqrt(flat[0]*flat[0]+flat[2]*flat[2]);Vec dir=flat/reach;
        for(int h=0;h<3;h++)
        {
            Vec eye=from+(Vec){0,0.45f+(float)h*0.75f,0};eye[1]+=surface_walk_height(eye[0],eye[2]);
            vpt::Pick see=vpt::world_pick({eye,dir});
            assert(!see.hit||see.rig>=0||see.distance>reach-c.radius,"Side cave mouth must be open at robot height, not sealed by the hill shell.");
        }
        vpt::Pick roof=vpt::world_pick({c.center+(Vec){0,1,2},{0,1,0}});
        assert(roof.hit&&roof.instance>=0&&vpt::assets[vpt::instances[roof.instance].asset].roof,"Every den needs a solid overhead ceiling.");
    }
    for(int f=0;f<32;f++)set_roof_visible(false);
    for(int i=0;i<vpt::instance_count;i++)if(vpt::assets[vpt::instances[i].asset].roof_group>0)assert(!vpt::hidden[i]&&vpt::roof_cutaway[i]==0,"Outside caves, all roofs stay opaque in top-down.");
    SurfaceCave cave=surface_caves[0];Vec at=cave.center;
    rl::RLCamera3D overhead={.position=at+(Vec){8,19,11},.target=at+(Vec){0,0.6f,0},.up={0,1,0},.fovy=42,.projection=rl::RLCameraProjection.PERSPECTIVE};
    habitat_capture(overhead,"dev/output/side-cave-outside.png");
    {
        Vec from=surface_stop(2,gen_seed);Vec dir=cave.center-from;dir[1]=0;dir=dir/math::sqrt(dir[0]*dir[0]+dir[2]*dir[2]);
        Vec eye=from-dir*3+(Vec){0,2.2f,0};
        rl::RLCamera3D mouth={.position=eye,.target=cave.center+(Vec){0,1.2f,0},.up={0,1,0},.fovy=60,.projection=rl::RLCameraProjection.PERSPECTIVE};
        habitat_capture(mouth,"dev/output/side-cave-mouth.png");
        for(int k=0;k<3;k++)
        {
            Vec spot=surface_stop(2+k*2,gen_seed);spot[1]=0.5f;float d=15.3f;
            rl::RLCamera3D top={.position=spot+(Vec){math::sin(0.68f)*math::cos(1.02f)*d,math::sin(1.02f)*d,math::cos(0.68f)*math::cos(1.02f)*d},.target=spot,.up={0,1,0},.fovy=32.78f,.projection=rl::RLCameraProjection.PERSPECTIVE};
            habitat_capture(top,rl::text_format("dev/output/side-cave-top-%d.png",k));
        }
    }
    vpt::Rig* me=&vpt::rigs[player];me.x=at[0];me.y=0.12f;me.z=at[2]+2;
    for(int f=0;f<32;f++)set_roof_visible(false);
    for(int i=0;i<vpt::instance_count;i++)if(vpt::assets[vpt::instances[i].asset].roof_group>0)
    {
        int group=vpt::assets[vpt::instances[i].asset].roof_group;
        assert(!vpt::hidden[i]);assert(group==1?vpt::roof_cutaway[i]>0.8f:vpt::roof_cutaway[i]==0,"Only the occupied cave roof should become transparent.");
    }
    vpt::Pick mouse=vpt::pick_scene({at+(Vec){0,12,2},{0,-1,0}},-1,false);
    assert(mouse.hit&&mouse.point[1]<1,"Top-down mouse picking must see through BOTH fine and coarse roof geometry.");
    vpt::Pick physical=vpt::world_pick({at+(Vec){0,1,2},{0,1,0}});
    assert(physical.hit&&physical.instance>=0&&vpt::assets[vpt::instances[physical.instance].asset].roof,"Camera/creature physics must still see the transparent roof.");
    vpt::Pick shot=vpt::shot_pick({at+(Vec){0,1,2},{0,1,0}},player);
    assert(shot.hit&&shot.distance<=physical.distance+0.01f,"Projectiles must not escape through the visual cutaway.");
    habitat_capture(overhead,"dev/output/side-cave-inside-top.png");
    for(int f=0;f<32;f++)set_roof_visible(true);
    for(int i=0;i<vpt::instance_count;i++)if(vpt::assets[vpt::instances[i].asset].roof_group>0)assert(vpt::roof_cutaway[i]==0,"V mode must keep an overhead roof, even inside.");
    Vec eye=at-cave.direction*(cave.radius-0.5f)+(Vec){0,1.45f,0};Vec entrance=at+(Vec){0,1.1f,0};
    habitat_capture({.position=eye,.target=entrance,.up={0,1,0},.fovy=65,.projection=rl::RLCameraProjection.PERSPECTIVE},"dev/output/side-cave-v.png");
    me=&vpt::rigs[player];me.x=at[0];me.z=at[2];me.y=surface_height(at[0],at[2],gen_seed)+0.2f;
    for(int f=0;f<32;f++)set_roof_visible(false);
    for(int i=0;i<vpt::instance_count;i++)if(vpt::assets[vpt::instances[i].asset].roof_group>0)assert(vpt::roof_cutaway[i]==0,"Standing ON a cave must not trigger its interior cutaway.");
    me.x=spawn[0];me.y=spawn[1];me.z=spawn[2];
    Vec eye2=spawn+(Vec){0,1.8f,0};
    {
        vpt::Rig* r0=&vpt::rigs[player];Vec robot_at={r0.x,r0.y+0.4f,r0.z};float d=15.3f;
        habitat_capture({.position=robot_at+(Vec){math::sin(0.68f)*math::cos(1.02f)*d,math::sin(1.02f)*d,math::cos(0.68f)*math::cos(1.02f)*d},.target=robot_at,.up={0,1,0},.fovy=32.78f,.projection=rl::RLCameraProjection.PERSPECTIVE},"dev/output/play-top.png",true);
        Vec behind=robot_at+(Vec){math::sin(0.68f)*3.2f,1.1f,math::cos(0.68f)*3.2f};
        habitat_capture({.position=behind,.target=robot_at+(Vec){-math::sin(0.68f)*12,0.9f,-math::cos(0.68f)*12},.up={0,1,0},.fovy=60,.projection=rl::RLCameraProjection.PERSPECTIVE},"dev/output/play-v.png",true);
    }
    habitat_capture({.position=eye2,.target=eye2+(Vec){0,3.3f,10},.up={0,1,0},.fovy=68,.projection=rl::RLCameraProjection.PERSPECTIVE},"dev/output/surface-galaxy.png",true);   // grid ON: the editor grid must not replace the sky
    // Exactly ONE crate on the surface, in the salvage den, holding one modifier; E opens it once.
    assert(game_item_count==1&&game_items[0].contained&&pickup_count==0,"Layer 0 has exactly one concealed upgrade.");
    int filled= -1;int crates=0;int contents=0;
    for(int i=0;i<vpt::instance_count;i++)if(salvage_crate(i)) { crates++;if(prop_loot[i]>=0) { filled=i;contents++; } }
    assert(crates==1&&contents==1,"Layer 0 has exactly one crate and it holds the upgrade.");
    int den=surface_cave_at(vpt::instances[filled].x,vpt::instances[filled].z);
    assert(den>=0&&surface_caves[den].content==0,"The crate sits in the salvage den.");
    vpt::Rig* opener=&vpt::rigs[player];opener.x=vpt::instances[filled].x+1.4f;opener.z=vpt::instances[filled].z;opener.y=vpt::instances[filled].y;
    assert(crate_in_reach()==filled,"Standing at the crate must offer E.");
    int before=pickup_count;crate_interact();
    assert(pickup_count==before+1&&prop_loot[filled]<0&&crate_in_reach()<0,"E must open the crate and hand over its modifier.");
    crate_interact();damage_prop(filled,{0,0,1},100);assert(pickup_count==before+1,"An opened crate must never give a second item.");
    int scav= -1;for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SCAVENGER) { scav=r;break; }
    assert(scav>=0);bool[6] activities;
    for(int trial=0;trial<96;trial++) { brood[scav].think=0;surface_idle(scav,1.0f/60);activities[brood[scav].activity]=true; }
    assert(activities[SURF_REST]&&activities[SURF_FORAGE]&&activities[SURF_GROOM]&&activities[SURF_SOCIAL]&&activities[SURF_PATROL],"Scavengers must have varied non-combat routines.");
    prop_destruction_check();
    { vpt::Rig* back=&vpt::rigs[player];back.x=spawn[0];back.y=spawn[1];back.z=spawn[2];debris_count=0;vpt::update_rigs(1.0f/60); }   // open ground for the weapon shots
    weapon_check();hit_feedback_check();skills_check();
    atmosphere_bench();
    {
        // Atmosphere look: robot near a side-cave mouth, low camera toward it (spores + drifting ash).
        SurfaceCave cv=surface_caves[1];Vec mouth=cv.center-cv.direction*6.5f;vpt::Rig* r0=&vpt::rigs[player];
        r0.x=mouth[0]-cv.direction[0]*4;r0.z=mouth[2]-cv.direction[2]*4;r0.y=surface_walk_height(r0.x,r0.z);motes_seeded=false;
        Vec low_eye={r0.x-cv.direction[0]*3,r0.y+1.4f,r0.z-cv.direction[2]*3};
        for(int f=0;f<30;f++) { game_time+=1.0f/60;vpt::update_rigs(1.0f/60);game_post(1.0f/60); }
        habitat_capture({.position=low_eye,.target=mouth+(Vec){0,1.2f,0},.up={0,1,0},.fovy=60,.projection=rl::RLCameraProjection.PERSPECTIVE},"dev/output/atmosphere-mouth.png");
    }
    habitat_flutter_check();
    surface_crater_check();surface_reaction_check();
    io::printfn("VPT SURFACE HABITAT CHECKS PASSED: galaxy, %d roof pieces, 3 entrances, conditional cutaway, %d crate (E), varied personalities",grouped,contents);
}
