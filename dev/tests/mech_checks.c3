module depths;
import std::math;
import std::io;
import raylib6::rl;
import vpt;
import libc;

// --game-test-mechs: the three player mechs (main menu choice) on surface:42. Each layer spawns the chosen
// rig, it carries only its own weapon, shots leave its own muzzles, the Mortar's launch shoves it back and
// bogs it down, and the speed ranking holds (Maul > Rattler > Mortar). Captures dev/output/mech-{0,1,2}-fire.png.
bool test_mechs;
fn void mech_checks()
{
    float[ROBOT_COUNT] want;float[ROBOT_COUNT] got;
    for(int k=0;k<ROBOT_COUNT;k++)
    {
        player_robot=k;
        assert(open_gen_spec("surface:42"),"surface:42 must generate.");
        int robot= -1;for(int r=0;r<vpt::rig_count;r++)if(is_player_rig(r))robot=r;
        assert(robot>=0&&robot_index(vpt::rigs[robot].def)==k,"The generator spawns the mech chosen in the menu.");
        vpt::begin_undo();vpt::controlled_rig=robot;game_start();assert(game_on,"The game starts with every mech.");
        assert(weapons_ready&&weapon==ROBOT_WEAPON[k],"The mech carries its own weapon (attachments loaded).");
        vpt::Rig* me=&vpt::rigs[player];god=true;
        Vec fwd=vpt::rig_dir(me,{0,0,1});Vec body={me.x,me.y+0.5f,me.z};Vec target=body+fwd*9;target[1]=me.y+0.4f;
        me.strafe_yaw=math::atan2(fwd[0],fwd[2]);weapon_frames(90,target);   // strafing mechs face their aim yaw
        for(int b=0;b<weapon_muzzles();b++)
        {
            Vec d=weapon_muzzle(b)-body;float l=math::sqrt(vpt::dot(d,d));
            assert(vpt::dot(nrm(d),fwd)>0.15f&&l<2.2f,"Muzzles sit at the front of the mech.");
        }
        // one trigger pull, as the game does it
        int before=bolt_count;Vec knock0=me.knock;
        if(weapon==W_SHOTGUN) { fire_shell(me,target);assert(bolt_count-before==9,"A shell is nine pellets."); }
        else { fire_shot(me,target,weapon==W_ROCKET);assert(bolt_count>before,"The shot leaves the muzzle."); }
        Vec dk=me.knock-knock0;float push=math::sqrt(vpt::dot(dk,dk));
        if(k==1) { assert(heavy_t>0&&push>7,"The Mortar's launch shoves it back hard and bogs it down."); }
        if(weapon==W_SHOTGUN) { int b0=barrel;fire_shell(me,target);assert(barrel!=b0,"The double barrel alternates barrels."); }
        // the shot in flight, side-on (bolts are frozen: only rigs/effects advance during the capture)
        Vec right={fwd[2],0,-fwd[0]};
        rl::RLCamera3D cam={.position=body+right*(k==1?5.0f:3.8f)+fwd*1.6f+(Vec){0,1.3f,0},.target=body+fwd*0.5f,.up={0,1,0},.fovy=45,.projection=rl::RLCameraProjection.PERSPECTIVE};
        habitat_capture(cam,rl::text_format("dev/output/mech-%d-fire.png",k));
        // top speed: walk forward 2 s (after the bog-down wore off), facing the walking direction
        bolt_count=0;heavy_t=0;me.knock={};float dt=1.0f/60;
        for(int f=0;f<30;f++) { game_update(dt,{target+(Vec){0,6,0},{0,-1,0}},true,false);vpt::update_rigs(dt);game_post(dt); }
        Vec p0={me.x,0,me.z};float run=0;
        for(int f=0;f<120;f++)
        {
            Vec ahead={me.x,me.y,me.z};ahead+=fwd*6;vpt::control_input=fwd;
            game_update(dt,{ahead+(Vec){0,6,0},{0,-1,0}},true,false);vpt::update_rigs(dt);game_post(dt);
            Vec p={me.x,0,me.z};Vec d=p-p0;run=math::max(run,vpt::dot(d,fwd));
        }
        vpt::control_input={};
        vpt::RigDef* d=&vpt::rig_defs[me.def];want[k]=d.speed*ROBOT_SPEED[k];got[k]=run/2;
        io::printfn("VPT MECH %s: weapon %s, %d muzzles, launch push %.1f, top speed %.2f m/s (walked %.2f m/s), grip %.2f m",
            ROBOT_NAMES[k],WEAPON_NAMES[weapon],weapon_muzzles(),push,want[k],got[k],ROBOT_GRIP[k]);
        assert(got[k]>want[k]*0.45f,"The mech actually walks near its top speed.");
        game_stop();
    }
    assert(want[2]>want[0]&&want[0]>want[1]&&got[2]>got[0]&&got[0]>got[1],"Speed ranking: Maul > Rattler > Mortar.");
    player_robot=0;
    io::printn("VPT MECH CHECKS PASSED: three mechs, own weapons and muzzles, Mortar recoil, speed ranking");
}

// --game-test-bestiary: kills land in the right species / mech, first kill pops the entry, the killer is
// remembered on death, and a profile survives a write/read round trip (in dev/output/save-home, never ~).
bool test_bestiary;
fn void bestiary_checks()
{
    (void)rl::make_directory("dev/output/save-home");libc::setenv("HOME",rl::text_format("%s/dev/output/save-home",rl::get_working_directory()),1);
    profile_erase(1);profile_select(1);assert(!profile.used&&total_kills(&profile)==0,"An empty slot starts fresh.");
    player_robot=2;assert(open_gen_spec("surface:42"));
    int robot= -1;for(int r=0;r<vpt::rig_count;r++)if(is_player_rig(r))robot=r;
    vpt::begin_undo();vpt::controlled_rig=robot;game_start();assert(game_on);
    int scav= -1;int stalker= -1;for(int r=0;r<vpt::rig_count;r++) { if(kind[r]==SCAVENGER&&scav<0)scav=r;if(kind[r]==STALKER&&stalker<0)stalker=r; }
    assert(scav>=0&&stalker>=0,"surface:42 has scavengers and stalkers.");
    assert(species_of(scav)==SP_SCAVENGER&&species_of(stalker)==SP_STALKER,"Species classification.");
    popup_t=0;kill_rig(scav,{1,0,0});
    assert(profile.kills[SP_SCAVENGER]==1&&profile.by_mech[SP_SCAVENGER*ROBOT_COUNT+2]==1&&profile.first[SP_SCAVENGER]>0,"A kill is counted per species and per mech (Maul).");
    assert(popup_t>0,"The first kill of a species announces the new bestiary entry.");
    assert(profile.used&&rl::file_exists(save_path(1)),"A discovery is saved right away.");
    for(int r=0;r<vpt::rig_count;r++)if(kind[r]==SCAVENGER) { popup_t=0;kill_rig(r,{1,0,0});assert(popup_t==0,"Repeat kills don't announce again.");break; }
    god=false;player_hp=1;robot_hit({1,0,0},50,1,SP_STALKER);if(player_hp<=0)die();
    assert(profile.deaths==1&&profile.killed_you[SP_STALKER]==1,"Death remembers the killer species.");
    int kills=profile.kills[SP_SCAVENGER];game_stop();
    Profile back;assert(profile_read(1,&back)&&back.kills[SP_SCAVENGER]==kills&&back.killed_you[SP_STALKER]==1&&back.deaths==1,"The profile survives a round trip.");
    profile_erase(1);assert(!rl::file_exists(save_path(1)),"Erase deletes the slot file.");
    save_slot= -1;profile={};player_robot=0;
    io::printfn("VPT BESTIARY CHECKS PASSED: species, per-mech kills, first-kill entry, killer on death, save round trip, erase (%d scavengers killed)",kills);
}
