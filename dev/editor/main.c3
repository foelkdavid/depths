module depths;
import std::io;
import raylib6::rl;
import vpt;
import vpt::ui;
import vpt::editor;
import vpt::audio;

// depths-dev: the vpt editor with Depths plugged in. P on a mech plays the real game; New World offers
// generated layers; the Depths test suites and benchmarks run from the command line.
fn void main(String[] args)
{
    editor::game={.init=&depths_world_init,.plays=&is_player_rig,.start=&plug_start,.stop=&game_stop,.active=&plug_active,.keys=&plug_keys,
        .escape=&plug_escape,.paused=&plug_paused,.mouse_blocked=&plug_mouse_blocked,.aim=&plug_aim,.update=&plug_update,.post=&game_post,
        .camera=&plug_camera,.hud=&draw_game_hud,.open_spec=&plug_open_spec};
    editor::add_world_button("Surface expedition (0)",&new_surface);editor::add_world_button("Caves only (-1)",&new_caves);
    editor::add_cli_tool(&depths_arg,&depths_run);
    editor::run(args);
}
const ZString ESC_TARGET="editor";   // what Esc does after death (game HUD hint)
fn void after_generated() => editor::after_generated();
fn void new_surface() => play_generated(0,true,0);
fn void new_caves() => play_generated(0,true,-1);

// ---------------------------------------------------------------- play mode
fn void plug_start(int rig) => game_start();
fn bool plug_active() => game_on;
fn bool plug_paused() => skills_open;   // the skill tree pauses the game
fn bool plug_mouse_blocked() => cheat_open&&ui::inside(cheat_rect.x,cheat_rect.y,cheat_rect.width,cheat_rect.height);
fn bool plug_escape() { if(skills_open) { toggle_skills();return true; }return false; }
fn void plug_keys()
{
    if(ui::key('r'))game_restart();
    if(ui::key('v'))toggle_third_person();
    if(!skills_open&&ui::key('e')) { if(crate_in_reach()>=0) { crate_interact(); } else { shop_interact(); } }
    if(ui::key('t'))toggle_skills();
    if(!skills_open&&(rl::is_key_pressed(rl::RLKeyboardKey.LEFT_SHIFT)||rl::is_key_pressed(rl::RLKeyboardKey.RIGHT_SHIFT)))dash_request=true;
    if(rl::is_key_pressed(rl::RLKeyboardKey.F2))cheat_open=!cheat_open;
    if(!skills_open&&rl::is_key_pressed(rl::RLKeyboardKey.F3))weapon_toggle_mount();
}
// Third person (V): the mouse is captured and the aim ray comes from the screen centre.
fn bool plug_aim(rl::RLRay* ray,float dt,bool focus)
{
    tp_update_capture(game_on&&third_person&&focus&&!cheat_open&&!skills_open&&rl::is_window_focused());
    bool tp=tp_active()&&!tp_snap;if(tp) { tp_input(dt);*ray=tp_aim_ray(); }
    return tp;
}
fn void plug_update(float dt,rl::RLRay ray,bool aiming,bool fire) { game_update(dt,ray,aiming,fire);apply_layer_transition(); }
fn rl::RLCamera3D plug_camera(int rig,rl::RLCamera3D cam,float dt)
{
    if(rig>=0)
    {
        vpt::Rig r=vpt::rigs[rig];if(game_on) { vpt::focus+=shake_offset();cam=vpt::camera(); }
        cam=swoosh(tp_active()?tp_camera(r,dt):cam,rl::get_frame_time());
        if(game_on)audio_update({r.x,r.y+1,r.z},cam);
    }
    set_roof_visible(tp_active()&&(cam_blend>=0.8f||!game_on));   // the cave roof only exists for the third-person camera (shown late in the swoosh in)
    return cam;
}
fn bool plug_open_spec(ZString spec) => is_gen_spec(spec)&&open_gen_spec(spec);

// ---------------------------------------------------------------- command line
ZString game_test_scene;bool test_audio;ZString cli_bench_views;bool cli_generate;bool cli_detail=true;int cli_layer;uint cli_seed;
fn int depths_arg(String[] args,int i)
{
    String a=args[i];bool more=i+1<(int)args.len;
    if(a=="--generate") { cli_generate=true;return 1; }
    if(a=="--detailed") { cli_detail=true;return 1; }
    if(a=="--coarse") { cli_detail=false;return 1; }
    if(a=="--seed"&&more) { cli_seed=(uint)(args[i+1].to_int()??0);return 2; }
    if(a=="--layer"&&more) { cli_layer=args[i+1].to_int()??0;return 2; }
    if(a=="--robot"&&more) { player_robot=vpt::clampi(args[i+1].to_int()??0,0,ROBOT_COUNT-1);return 2; }   // generated layers: 0 Rattler, 1 Mortar, 2 Maul
    if(a=="--cli_bench-views"&&more) { cli_bench_views=(ZString)args[i+1].ptr;editor::headless=true;return 2; }
    if(a=="--game-test-bestiary") { game_test_scene="surface:42";test_bestiary=true;editor::headless=true;return 1; }
    if(a=="--game-test-mechs") { game_test_scene="surface:42";test_mechs=true;editor::headless=true;return 1; }
    if(!a.starts_with("--game-test")||!more)return 0;
    if(a=="--game-test-sounds") { test_audio=true;test_environment_audio=true; }
    else if(a=="--game-test-audio") { test_audio=true;test_all_mods=true; }
    else if(a=="--game-test-boss-v") { test_boss_v=true; }
    else if(a=="--game-test-habitat") { test_habitat=true; }
    else if(a=="--game-test-layers") { test_layers=true; }
    else if(a=="--game-test-aim") { test_aim=true; }
    else if(a=="--game-test-ai") { test_ecology=true;test_audio=true; }
    else if(a=="--game-test-mods") { test_all_mods=true; }
    else if(a!="--game-test") { return 0; }
    game_test_scene=(ZString)args[i+1].ptr;editor::headless=true;return 2;
}
fn bool depths_run()
{
    if(game_test_scene) { if(test_audio) { audio::allowed=true;audio::master=0; }game_test(game_test_scene,20);return true; }
    if(cli_bench_views) { run_view_benchmark(cli_bench_views);return true; }
    if(cli_generate)play_generated(cli_seed,cli_detail,cli_layer);   // then the editor runs with the new layer
    return false;
}
