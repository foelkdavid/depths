module depths;
import std::math;
import std::encoding::json;
import raylib6::rl;
import vpt;

// Depths data stored with a scene (game rooms/doors/items, the generator record) and the engine hooks that
// let generated layers behave: rebake on load, no-fly volumes, see-through side-cave lids, the galaxy sky.
// Optional gameplay layout (game.c3): rooms (kind 0 normal, 1 start, 2 treasure, 3 boss), doors between
// two rooms (axis 0: the passage runs along x, 1: along z), item pickups. Absent in editor scenes.
struct GameRoomFile { float x0;float z0;float x1;float z1;int kind; }
struct GameDoorFile { float x;float z;int axis;int a;int b; }
struct GameItemFile { float x;float z;int kind;bool contained; }   // contained: bind to the service crate at x/z, reveal only when it breaks
struct GameFile { GameRoomFile[] rooms;GameDoorFile[] doors;GameItemFile[] items; }
struct GeneratorFile { long seed;int detailed;int version;int layer; }   // procedural layer: generated ("gen:") assets are re-baked from the seed on load
const int MAX_GAME_ROOMS=64;
GameRoomFile[MAX_GAME_ROOMS] game_rooms;int game_room_count;
GameDoorFile[128] game_doors;int game_door_count;
GameItemFile[16] game_items;int game_item_count;
struct DepthsSceneFile { GameFile game;GeneratorFile generator; }
int surface_cutaway_cave= -1;   // the side cave whose lid is faded right now (set_roof_visible)
const ZString GALAXY_SKY="assets/skies/ash-waste-galaxy.png";

fn void depths_world_init()
{
    vpt::on_new_scene=&depths_new_scene;vpt::on_scene_save=&depths_scene_save;vpt::on_scene_check=&depths_scene_check;vpt::on_scene_loaded=&depths_scene_loaded;
    vpt::flight_allowed=&depths_flight_allowed;vpt::terrain_see_through=&depths_see_through;
    vpt::set_sky_map(GALAXY_SKY);vpt::sky_map_moon=0.15f;vpt::sky_map_fill=0.42f;   // user: "make l0 darker"
}
fn void depths_new_scene() { game_room_count=0;game_door_count=0;game_item_count=0;gen_active=false;gen_layer= -1;surface_cutaway_cave= -1; }
// Layer 0 (the surface) shows the galaxy and its visible ground is detail geometry (shots hit it, not the hidden 1 m terrain).
fn void depths_layer_flags() { bool surface=gen_active&&gen_layer==0;vpt::sky_map_on=surface;vpt::shots_hit_floor=surface; }
fn ZString depths_scene_save()
{
    DepthsSceneFile f={{game_rooms[:game_room_count],game_doors[:game_door_count],game_items[:game_item_count]},{gen_active?(long)gen_seed:0,gen_active&&gen_detailed?1:0,gen_layer==0?SURFACE_GEN_VERSION:1,gen_layer}};
    String s=json::marshal(tmem,f);return (ZString)string::tformat("%s",s[1:s.len-2]).zstr_tcopy();
}
fn bool depths_scene_check(String source)
{
    DepthsSceneFile f;if(try parsed=json::unmarshal(tmem,source,DepthsSceneFile)) { f=parsed; } else { return true; }
    GeneratorFile g=f.generator;
    if(g.seed>0&&(g.version<0||g.version>SURFACE_GEN_VERSION||(g.version>=1&&g.layer!=0&&g.layer!= -1))) { vpt::report("Unsupported generated layer.");return false; }
    return true;
}
fn bool depths_scene_loaded(String source)
{
    DepthsSceneFile f;if(try parsed=json::unmarshal(tmem,source,DepthsSceneFile)) { f=parsed; } else { return true; }
    game_room_count=0;game_door_count=0;game_item_count=0;
    foreach(gr:f.game.rooms)if(game_room_count<MAX_GAME_ROOMS)game_rooms[game_room_count++]=gr;
    foreach(gd:f.game.doors)if(game_door_count<128&&gd.a>=0&&gd.b>=0&&gd.a<game_room_count&&gd.b<game_room_count)game_doors[game_door_count++]=gd;
    foreach(gi:f.game.items)if(game_item_count<16)game_items[game_item_count++]=gi;
    if(f.generator.seed>0)
    {
        gen_active=true;gen_seed=(uint)f.generator.seed;gen_detailed=f.generator.detailed!=0;
        gen_layer=f.generator.version>=1?f.generator.layer:-1;   // old saves are caves, never surface
        surface_cave_version=math::max(f.generator.version,1);   // v1 surfaces keep their outward-facing dens
        if(!gen_detailed)vpt::make_props_unique();
        if(gen_detailed) { bool baked=gen_layer==0?bake_surface_detail(gen_seed):bake_cave_detail(gen_seed);if(!baked)gen_detailed=false; }
    }
    depths_layer_flags();return true;
}
fn bool depths_flight_allowed(Vec p)
{
    if(gen_active&&gen_layer== -1&&vpt::terrain_hidden)
    {
        // No flying over the collision rock or through the hidden ceiling into the void.
        if(vpt::solid_terrain(p[0],0.5f,p[2])||p[1]>roof_under(p[0],p[2],gen_seed)-0.08f)return false;
    }
    if(gen_active&&gen_layer==0)
    {
        if(vpt::solid_terrain(p[0],p[1]+0.08f,p[2]))return false;
        int cave=surface_cave_at(p[0],p[2]);
        if(cave>=0)
        {
            float roof=surface_cave_ceiling(cave,p[0],p[2]);float top=surface_height(p[0],p[2],gen_seed);
            if(top>roof+0.3f&&p[1]>roof-0.08f&&p[1]<top+0.15f)return false;
        }
    }
    return true;
}
// Gameplay picking ignores the coarse roof voxels of the side cave whose lid is faded out (top-down view).
fn bool depths_see_through(int x,int y,int z)
{
    if(surface_cutaway_cave<0||!gen_active||gen_layer!=0)return false;
    float fx=(float)x+0.5f;float fz=(float)z+0.5f;int c=surface_cutaway_cave;
    return surface_cave_open(c,fx,fz)>0&&(float)y>=surface_cave_ceiling(c,fx,fz);
}
