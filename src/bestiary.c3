module depths;
import std::math;
import std::io;
import std::encoding::json;
import std::time;
import raylib6::rl;
import vpt;
import libc;

// Bestiary + save slots. A species is "discovered" once you killed one. Every kill is counted per species and
// per mech; deaths remember which species landed the last hit. The profile (3 slots) lives in
// ~/.local/share/depths/slot-N.json and is written ONLY when a slot is active (the game app sets save_slot);
// the editor and every test mode keep it in memory and never touch the files.
// Species ids are stored by index in the files: only ever APPEND new species.
const int SP_SKITTER=0;const int SP_CRAWLER=1;const int SP_BROOD=2;const int SP_NEST=3;const int SP_SPIRE=4;
const int SP_BLOATER=5;const int SP_FLUTTER=6;const int SP_SCAVENGER=7;const int SP_STALKER=8;const int SPECIES_COUNT=9;
struct Species { ZString name;ZString proxy;ZString habitat;ZString threat;int hp;ZString lore; }
const Species[SPECIES_COUNT] SPECIES={
    {"ALIEN SKITTER","alien-skitter","Layer -1  /  side dens","LOW",2,
     "Hand-sized hatchlings that pour out of nests and scuttle over walls and ceilings. Alone a nuisance; a disturbed colony is a flood. Rarely hops."},
    {"ALIEN CRAWLER","alien-crawler","Layer -1","MEDIUM",16,
     "Ten-legged cave hunter. Runs along the walls, climbs onto the roof, roars the moment it sees you and rushes. Often carries a shop key."},
    {"BROOD CRAWLER","alien-crawler","Boss den of every layer","EXTREME",60,
     "The giant crawler guarding a layer's rift. It waits in its den until you come in. Kill it and the rift wakes up."},
    {"ALIEN NEST","alien-nest","Layer -1  /  boss dens","MEDIUM",7,
     "A pulsing hive grown onto floor, wall or ceiling. Hatches skitters every few seconds and bursts into a brood when destroyed."},
    {"NEST SPIRE","alien-nest-spire","Layer -1","MEDIUM",12,
     "A tall hive column, anchored to the rock by strands. Tougher than a nest, same angry brood inside."},
    {"BLOATER","alien-bloater","Layer -1","HIGH",3,
     "A slow, swollen kamikaze. Close in, it lights a fuse, swells and strobes red, then bursts. Its blast sets off the next one."},
    {"CAVE-WING","alien-flutter","Layer -1  /  boss dens","LOW",3,
     "Six legs, four wings. Perches on the rock and clicks, takes short flights, flees at first and only fights back when cornered."},
    {"ASH SCAVENGER","ash-scavenger","Layer 0  /  the ash waste","LOW",3,
     "A plated six-legged forager that sniffs around fossils and crates in small packs. Shy ones bolt; bold ones and the whole pack retaliate."},
    {"DUNE STALKER","dune-stalker","Layer 0  /  the ash waste","HIGH",12,
     "A tall four-legged ridge hunter. Watches from high ground, rears back with a roar, braces, then charges in a straight line. Sidestep it."},
};
fn int species_of(int r)
{
    if(r<0||r>=vpt::rig_count)return -1;int def=vpt::rigs[r].def;float s=vpt::rigs[r].scale;
    switch(kind[r])
    {
        case SKITTER: return SP_SKITTER;
        case CRAWLER: return s>1.3f?SP_BROOD:SP_CRAWLER;
        case NEST: return def_named(def,"spire")?SP_SPIRE:SP_NEST;
        case BLOATER: return SP_BLOATER;
        case FLUTTER: return SP_FLUTTER;
        case SCAVENGER: return SP_SCAVENGER;
        case STALKER: return SP_STALKER;
        default: return -1;
    }
}

// ---------------------------------------------------------------- profile (one save slot)
const int SAVE_SLOTS=3;
struct Profile
{
    bool used;int[SPECIES_COUNT] kills;long[SPECIES_COUNT] first;int[SPECIES_COUNT*ROBOT_COUNT] by_mech;int[SPECIES_COUNT] killed_you;
    int runs;int deaths;int deepest;double play_time;long created;long last_played;
}
struct ProfileFile { int version;int[] kills;long[] first;int[] by_mech;int[] killed_you;int runs;int deaths;int deepest;double play_time;long created;long last_played; }
Profile profile;int save_slot= -1;bool profile_dirty;float profile_autosave;int last_hit_species= -1;
fn long now_seconds() => (long)time::now().to_seconds();
fn int discovered_count(Profile* p) { int n=0;for(int s=0;s<SPECIES_COUNT;s++)if(p.kills[s]>0)n++;return n; }
fn int total_kills(Profile* p) { int n=0;for(int s=0;s<SPECIES_COUNT;s++)n+=p.kills[s];return n; }

fn ZString save_dir()
{
    ZString home=libc::getenv("HOME");return home?rl::text_format("%s/.local/share/depths",home):"depths-saves";
}
fn ZString save_path(int slot) => rl::text_format("%s/slot-%d.json",save_dir(),slot+1);
fn bool profile_read(int slot,Profile* p)
{
    *p={};ZString path=save_path(slot);if(!rl::file_exists(path))return false;
    char* text=rl::load_file_text(path);if(!text)return false;defer rl::unload_file_text((ZString)text);
    ProfileFile f;if(try parsed=json::unmarshal(tmem,((ZString)text).str_view(),ProfileFile)) { f=parsed; } else { return false; }
    p.used=true;
    for(int s=0;s<SPECIES_COUNT;s++)
    {
        if(s<(int)f.kills.len)p.kills[s]=math::max(0,f.kills[s]);if(s<(int)f.first.len)p.first[s]=f.first[s];
        if(s<(int)f.killed_you.len)p.killed_you[s]=math::max(0,f.killed_you[s]);
    }
    for(int i=0;i<SPECIES_COUNT*ROBOT_COUNT&&i<(int)f.by_mech.len;i++)p.by_mech[i]=math::max(0,f.by_mech[i]);
    p.runs=f.runs;p.deaths=f.deaths;p.deepest=f.deepest;p.play_time=math::is_finite(f.play_time)?f.play_time:0;p.created=f.created;p.last_played=f.last_played;
    return true;
}
fn void profile_write()
{
    if(save_slot<0)return;
    @pool()
    {
        (void)rl::make_directory(save_dir());
        DString s=dstring::temp();Profile* p=&profile;if(!p.created)p.created=now_seconds();p.last_played=now_seconds();
        s.appendf("{\"version\":1,\n \"kills\":[");for(int i=0;i<SPECIES_COUNT;i++)s.appendf("%s%d",i?",":"",p.kills[i]);
        s.appendf("],\n \"first\":[");for(int i=0;i<SPECIES_COUNT;i++)s.appendf("%s%d",i?",":"",p.first[i]);
        s.appendf("],\n \"by_mech\":[");for(int i=0;i<SPECIES_COUNT*ROBOT_COUNT;i++)s.appendf("%s%d",i?",":"",p.by_mech[i]);
        s.appendf("],\n \"killed_you\":[");for(int i=0;i<SPECIES_COUNT;i++)s.appendf("%s%d",i?",":"",p.killed_you[i]);
        s.appendf("],\n \"runs\":%d,\"deaths\":%d,\"deepest\":%d,\"play_time\":%.1f,\"created\":%d,\"last_played\":%d}\n",p.runs,p.deaths,p.deepest,p.play_time,p.created,p.last_played);
        // write next to it, then rename: a crash mid-write never eats the slot
        ZString tmp=rl::text_format("%s.tmp",save_path(save_slot));
        if(rl::save_file_text(tmp,s.zstr_view()))(void)libc::rename(tmp,save_path(save_slot));
    };
    profile.used=true;profile_dirty=false;profile_autosave=0;
}
// Make `slot` the active profile (loads it; an empty slot starts fresh and is created on its first save).
fn void profile_select(int slot)
{
    if(save_slot>=0&&profile_dirty)profile_write();
    save_slot=math::clamp(slot,0,SAVE_SLOTS-1);if(!profile_read(save_slot,&profile))profile={};profile_dirty=false;
}
fn void profile_erase(int slot)
{
    (void)libc::remove(save_path(slot));if(slot==save_slot) { profile={};profile_dirty=false; }
}
fn void profile_flush() { if(profile_dirty)profile_write(); }

// ---------------------------------------------------------------- game hooks
// A creature died (any cause during a run counts: your rockets, a bloater chain, a nest you burst).
fn void bestiary_kill(int r)
{
    int s=species_of(r);if(s<0)return;
    bool first=profile.kills[s]==0;profile.kills[s]++;profile.by_mech[s*ROBOT_COUNT+robot_of(player)]++;profile_dirty=true;
    if(first)
    {
        profile.first[s]=now_seconds();
        popup_title=rl::text_format("NEW BESTIARY ENTRY:  %s",SPECIES[s].name);popup_info="see the bestiary in the main menu";popup_color=0xe0a020;popup_t=POPUP_TIME;
        profile_flush();   // discoveries are saved right away
    }
}
fn void bestiary_death()
{
    profile.deaths++;if(last_hit_species>=0&&last_hit_species<SPECIES_COUNT)profile.killed_you[last_hit_species]++;profile_dirty=true;profile_flush();
}
fn void bestiary_run_started() { profile.runs++;profile_dirty=true;last_hit_species= -1; }
fn void bestiary_tick(float dt)
{
    profile.play_time+=dt;if(gen_active&&-gen_layer>profile.deepest) { profile.deepest= -gen_layer;profile_dirty=true; }
    profile_autosave+=dt;if(profile_autosave>20) { profile_autosave=0;profile_dirty=true;profile_flush(); }
}
