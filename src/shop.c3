module depths;
import std::math;
import raylib6::rl;
import vpt;

// The shop: one dead-end room per generated level (room kind 4), behind a bulkhead door with a status LED
// (red = locked, green = unlocked). Big creatures drop keys; E at the door spends one and unlocks it, after
// which the door opens by itself whenever the robot is near. Inside, a control console = SKILL STATION:
// E opens the skill tree (paused) with +1 skill point the first time and one full respec (skills.c3).
// The console glows while it still has something to give.

const int KEY_KIND=99;   // pickup kind of a key (every other kind is a free perk)
int shop_room= -1;int shop_door= -1;bool shop_unlocked;float shop_door_open;
int keys;int keys_dropped;float shop_time;Vec shop_console;
int console_asset= -1;

fn void shop_init()
{
    shop_room= -1;shop_door= -1;shop_unlocked=false;shop_door_open=0;keys=0;keys_dropped=0;station_point_taken=false;station_respec_used=false;
    for(int k=0;k<game_room_count;k++)if(game_rooms[k].kind==4)shop_room=k;
    if(shop_room<0)return;
    for(int k=0;k<game_door_count;k++)if(game_doors[k].a==shop_room||game_doors[k].b==shop_room)shop_door=k;
    GameRoomFile g=game_rooms[shop_room];shop_console={(g.x0+g.x1)*0.5f,0,(g.z0+g.z1)*0.5f};
    if(shop_door<0)shop_room= -1;   // no way in: treat as no shop
}
fn Vec shop_door_pos() { GameDoorFile d=game_doors[shop_door];return {d.x,0,d.z}; }
fn float flat_dist(Vec a,Vec b) { Vec d=a-b;d[1]=0;return math::sqrt(vpt::dot(d,d)); }

// Door + blocker, every frame (replaces the old room-lock gates).
fn void shop_update(float dt)
{
    vpt::blocker_count=0;shop_time+=dt;
    if(shop_room<0||player<0||player>=vpt::rig_count)return;
    vpt::Rig* me=&vpt::rigs[player];Vec p={me.x,0,me.z};
    bool want=shop_unlocked&&flat_dist(p,shop_door_pos())<4.5f;
    float before=shop_door_open;shop_door_open=vpt::clampf(shop_door_open+(want?1.0f:-1.0f)*dt*3.0f,0,1);
    GameDoorFile dr=game_doors[shop_door];
    if((before==0&&shop_door_open>0)||(before==1&&shop_door_open<1))audio::play_sound(SND_DOOR,{dr.x,1.5f,dr.z},1.1f,jitter(0.05f),true,false,0);
    if(shop_door_open<0.6f&&vpt::blocker_count<32)
    { vpt::blockers[vpt::blocker_count++]=dr.axis==0?(vpt::Blocker){dr.x-0.4f,dr.z-2.2f,dr.x+0.4f,dr.z+2.2f}:(vpt::Blocker){dr.x-2.2f,dr.z-0.4f,dr.x+2.2f,dr.z+0.4f}; }
}
// What E would do right now (also drives the on-screen prompt). 0 nothing, 1 unlock door, 2 locked/no key, 3 skill station.
fn int shop_action()
{
    if(shop_room<0||player<0||player>=vpt::rig_count||game_over||skills_open)return 0;
    vpt::Rig* me=&vpt::rigs[player];Vec p={me.x,0,me.z};
    if(!shop_unlocked&&flat_dist(p,shop_door_pos())<3.4f)return keys>0?1:2;
    if(shop_unlocked&&flat_dist(p,shop_console)<2.8f)return 3;
    return 0;
}
fn void shop_interact()
{
    switch(shop_action())
    {
        case 1:
            keys--;shop_unlocked=true;Vec d=shop_door_pos();
            audio::play_sound(SND_PICKUP,{},0.9f,0.8f,false,false,0);flash(d+(Vec){0,2.9f,0},{20,120,40},6,0.5f);
            popup_title="SKILL STATION UNLOCKED";popup_info="the door opens when you come near";popup_color=0x50e070;popup_t=POPUP_TIME;
        case 2:
            vpt::report("Locked. The big crawlers carry keys.");popup_title="LOCKED";popup_info="needs a key - big creatures drop them";popup_color=0x3c3cf0;popup_t=POPUP_TIME*0.7f;
        case 3:
            open_skill_station();
        default:
    }
}
// World objects: the door (sinks into the floor when open), its LEDs, the console's status glow.
fn void shop_draw()
{
    if(shop_room<0)return;
    GameDoorFile dr=game_doors[shop_door];
    if(gate_asset>=0&&shop_door_open<1)
    {
        vpt::Instance g={gate_asset,dr.x,-3.6f*shop_door_open,dr.z,dr.axis==0?1.5707963f:0,gate_scale,0};
        int id=vpt::dyn_add(g,vpt::QID);vpt::dyn_set_prev(id,g,vpt::QID);
    }
    // status LEDs above the doorway, one on each face; locked blinks slowly
    uint led=shop_unlocked?0x40ff40:0x2020ff;float on=shop_unlocked?1:(math::sin(shop_time*3)>-0.3f?1:0.25f);
    Vec n=dr.axis==0?(Vec){1,0,0}:(Vec){0,0,1};
    for(int s= -1;s<=1;s+=2)
    {
        Vec p=(Vec){dr.x,3.05f,dr.z}+n*(0.5f*(float)s);
        vpt::Instance l={bolt_asset,p[0],p[1],p[2],0,0.09f,0};int id=vpt::dyn_add(l,vpt::QID,led,true);vpt::dyn_set_prev(id,l,vpt::QID);
        vpt::game_light(p+n*(0.15f*(float)s),(shop_unlocked?(Vec){10,60,10}:(Vec){70,6,4})*on,3,vpt::instance_count+vpt::rig_part_count+id+1);
    }
    if(shop_unlocked&&station_live())vpt::game_light(shop_console+(Vec){0,1.6f,0},{60,40,10},5);   // the station still has a point / respec
}
// Prompt + key counter.
fn void shop_draw_ui(rl::RLRectangle view)
{
    int x=(int)view.x+16;int y=(int)view.y+140;
    if(keys>0) { rl::draw_rectangle_rounded({(float)x,(float)y,96,22},0.3f,4,{29,32,33,210});rl::draw_rectangle(x+6,y+7,10,8,{255,192,32,255});ui::text(rl::text_format("KEY x%d",keys),x+22,y+4,13,ui::ACCENT); }
    int act=shop_action();if(!act&&!skills_open&&crate_in_reach()>=0)act=4;
    if(act)
    {
        ZString s=act==1?"E  unlock the skill station (uses 1 key)":act==2?"Locked  -  big creatures drop keys":act==4?"E  open the crate  (free perk)":station_live()?"E  skill station  (+1 point, respec)":"E  skill station";
        int w=ui::text_width(s,18)+28;int cx=(int)(view.x+view.width/2);int cy=(int)(view.y+view.height*0.7f);
        rl::draw_rectangle_rounded({(float)(cx-w/2),(float)cy,(float)w,34},0.3f,6,{29,32,33,220});ui::text(s,cx-w/2+14,cy+8,18,act==2?ui::BAD:ui::ACCENT);
    }
}
