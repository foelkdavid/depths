module depths;
import std::math;
import raylib6::rl;
import vpt;

// Layer 0: continuous outdoor badlands, not the cave floor plan. The expedition trail is guaranteed open;
// mesas, salt flats and winding ridges grow around it. Field functions depend only on the seed (save/load).
int gen_layer= -1;
// Player mechs (main menu choice): HX-6 "Rattler" (machine gun), BR-4 "Mortar" (rockets), CQ-1 "Maul" (shotgun).
// Generated layers spawn the chosen one; game.c3 maps the def back to its weapon and handling.
const int ROBOT_COUNT=3;
const ZString[ROBOT_COUNT] ROBOT_RIGS={"maintenance-hexapod","br4-mortar","cq1-maul"};
int player_robot;
const int SURFACE_STOPS=7;
fn Vec surface_stop(int i,uint seed)
{
    const Vec[7] STOPS={{-36,0,31},{-23,0,12},{-5,0,23},{15,0,5},{-6,0,-9},{10,0,-28},{34,0,-31}};
    Vec p=STOPS[vpt::clampi(i,0,6)];
    p[0]+=(vpt::hash2(i,9,seed)-0.5f)*5;p[2]+=(vpt::hash2(i,21,seed)-0.5f)*5;return p;
}
fn float surface_trail(float x,float z,uint seed)
{
    Vec p={x,0,z};float best=1e9f;
    for(int i=0;i<SURFACE_STOPS-1;i++)
    {
        Vec a=surface_stop(i,seed);Vec ab=surface_stop(i+1,seed)-a;
        float t=vpt::clampf(vpt::dot(p-a,ab)/vpt::dot(ab,ab),0,1);Vec dv=p-a-ab*t;best=math::min(best,math::sqrt(vpt::dot(dv,dv)));
    }
    return best;
}
fn float surface_height(float x,float z,uint seed)
{
    init_surface_caves(seed);
    // An uneven radial escarpment, not four ruler-straight walls at the square world boundary.
    float radius=math::sqrt(x*x+z*z);float angle=math::atan2(z,x);
    float rim_start=48+math::sin(angle*3+0.8f)*2+vpt::vnoise(math::cos(angle)*3+7,math::sin(angle)*3,seed+90)*4;
    float rim=vpt::smooth(rim_start,rim_start+12,radius)*(7+vpt::vnoise(math::cos(angle)*4,math::sin(angle)*4+9,seed+91)*5);
    float band=math::abs(math::sin(z*0.105f+math::sin(x*0.067f)*2.3f+(float)(seed%31)*0.1f));
    float ridge=1-vpt::smooth(0.1f,0.38f,band);
    float h=ridge*ridge*(2.8f+vpt::vnoise(x*0.055f,z*0.055f,seed+61)*3.5f);
    float trail=surface_trail(x,z,seed);float clear=vpt::smooth(3.8f,7.5f,trail);h*=clear;rim*=clear;
    for(int i=0;i<SURFACE_STOPS;i++)
    { Vec p=surface_stop(i,seed);float d=math::sqrt((x-p[0])*(x-p[0])+(z-p[2])*(z-p[2]));float open=vpt::smooth(i==6?7.0f:4.0f,i==6?10.0f:6.0f,d);h*=open;rim*=open; }
    float ripples=0.025f*math::sin(x*4.5f+math::sin(z*0.7f)*1.8f);
    return 0.1f+math::max(math::max(rim,h),surface_mound(x,z))+ripples;
}
fn uint surface_color(float x,float y,float z,uint seed)
{
    float salt=vpt::vnoise(x*0.08f,z*0.08f,seed+11);float dust=vpt::vnoise(x*0.19f,z*0.19f,seed+12);
    float h=surface_height(x,z,seed);float[3] c;
    if(h>0.65f)
    {
        float band=0.5f+0.5f*math::sin(y*5.5f+vpt::vnoise(x*0.16f,z*0.16f,seed+13)*2);
        c={55+band*30,57+band*23,52+band*17};
        if(y>2.5f&&band>0.6f) { c[0]+=23;c[1]+=15;c[2]+=5; }
    }
    else
    {
        c={97+dust*31,86+dust*28,66+dust*25};
        float s=vpt::smooth(0.56f,0.76f,salt);c[0]=vpt::mixf(c[0],179,s);c[1]=vpt::mixf(c[1],173,s);c[2]=vpt::mixf(c[2],146,s);
        // Dark dried fissures in the salt, long wind-combed ribbons in the dust.
        float crack=math::abs(vpt::vnoise(x*0.9f,z*0.9f,seed+14)-0.5f);
        if(crack<0.016f&&salt>0.55f) { c[0]*=0.55f;c[1]*=0.55f;c[2]*=0.52f; }
        float ripple=math::sin(x*4.5f+math::sin(z*0.7f)*1.8f);for(int i=0;i<3;i++)c[i]+=ripple*4;
    }
    return vpt::rgba(vpt::clampi((int)c[0],0,255),vpt::clampi((int)c[1],0,255),vpt::clampi((int)c[2],0,255));
}
fn bool bake_surface_detail(uint seed)
{
    init_surface_caves(seed);
    for(int bz=0;bz<32;bz++)for(int bx=0;bx<32;bx++)
    {
        float x0=(float)(bx*4-64);float z0=(float)(bz*4-64);
        float edge=math::max(math::abs(x0+2),math::abs(z0+2));float center=surface_height(x0+2,z0+2,seed);
        float v=edge>51?0.5f:center>1.5f&&surface_trail(x0+2,z0+2,seed)>9?0.25f:0.125f;
        int n=(int)math::round(4/v);float lo=1e9f;float hi= -1e9f;float[32*32] height;
        for(int z=0;z<n;z++)for(int x=0;x<n;x++)
        { float h=surface_height(x0+((float)x+0.5f)*v,z0+((float)z+0.5f)*v,seed);height[z*n+x]=h;lo=math::min(lo,h);hi=math::max(hi,h); }
        float base=math::floor((lo-0.4f)/v)*v;int dy=(int)math::ceil((hi-base)/v)+1;
        if((long)vpt::active_asset_pixels()+(long)n*n*dy>GEN_ATLAS_BUDGET-1500000) { vpt::report("Surface terrain exceeds atlas budget.");return false; }
        Asset a={};if(!vpt::allocate_asset(&a,n,dy,n,v))return false;
        a.ground=true;a.no_pick=hi<0.5f;
        for(int z=0;z<3&&!a.roof_group;z++)for(int x=0;x<3&&!a.roof_group;x++)a.roof_group=surface_roof_group(x0+0.2f+(float)x*1.8f,z0+0.2f+(float)z*1.8f);
        int roof_group=a.roof_group;a.roof_group=0;
        bool near_cave=false;
        for(int i=0;i<3;i++) { SurfaceCave c=surface_caves[i];float ex=x0+2-c.center[0];float ez=z0+2-c.center[2];if(ex*ex+ez*ez<(c.radius+17)*(c.radius+17))near_cave=true; }
        for(int z=0;z<n;z++)for(int x=0;x<n;x++)
        {
            float wx=x0+((float)x+0.5f)*v;float wz=z0+((float)z+0.5f)*v;float top=height[z*n+x];
            float under=math::min(math::min(surface_height(wx-v,wz,seed),surface_height(wx+v,wz,seed)),math::min(surface_height(wx,wz-v,seed),surface_height(wx,wz+v,seed)))-v*2;
            // Side caves: the hill skin never reaches below the cave's own roof shell. Over the open
            // entrance cut (hill lower than roof+shell) the column is empty sky, so the mouth reads open.
            // Flat ground (<= 0.45 m) stays: the den floor shell only starts where the hill does.
            float lid= -1e9f;
            if(near_cave) { int cave=surface_cave_at(wx,wz);if(cave>=0&&top>0.45f) { lid=surface_cave_ceiling(cave,wx,wz)+0.3f;if(top<=lid)continue; } }
            for(int y=0;y<dy;y++)
            { float wy=base+((float)y+0.5f)*v;if(wy<=top&&wy>=under&&wy>=lid)a.data[(y*n+z)*n+x]=surface_color(wx,wy,wz,seed); }
        }
        if(roof_group>0)split_surface_roof(&a,x0,z0,base,roof_group);
        int id=vpt::add_generated_asset(&a,rl::text_format("surface-%d-%d",bx,bz));
        if(id>=0)vpt::instances[vpt::instance_count++]={id,x0+2,base,z0+2,0,1,0};
    }
    bake_surface_caves(seed);vpt::terrain_hidden=true;   // fine exterior + interior shells replace coarse roof voxels too
    vpt::make_props_unique((long)vpt::MAX_ATLAS_PIXELS-900000-(long)vpt::active_asset_pixels());return true;
}
fn void surface_prop(ZString name,float x,float z,float scale,float yaw=0)
{
    int id=vpt::import_asset(rl::text_format("%swastes/%s.vpt.json",GEN_LIB,name));if(id<0||vpt::instance_count>=vpt::MAX_INSTANCES)return;
    vpt::instances[vpt::instance_count++]={id,x,surface_walk_height(x,z),z,yaw,scale,0};
}
fn bool generate_surface(uint seed,bool detailed=true)
{
    vpt::new_scene(GEN_SIZE);vpt::release_assets();gen_layer=0;gen_active=true;gen_seed=seed;gen_detailed=detailed;surface_cave_version=SURFACE_GEN_VERSION;depths_layer_flags();
    gen_rng=seed*2654435761u|1;for(int i=0;i<8;i++)grand();
    vpt::lighting={210.91f,24.19f,2.92f,0.601f,1,0.64f,0.602f,0.85f,2,1,0,0};   // the user's layer-0 night: low moon behind the play view, warm fill
    // Coarse collision terrain under the sculpted shell. Ridges are solid; the expedition trail stays level.
    for(int z= -64;z<64;z++)for(int x= -64;x<64;x++)
    {
        int top=(int)math::floor(surface_height((float)x+0.5f,(float)z+0.5f,seed)-0.06f);
        int cave=surface_cave_at((float)x+0.5f,(float)z+0.5f);
        float ceiling=cave>=0?surface_cave_ceiling(cave,(float)x+0.5f,(float)z+0.5f):0;
        for(int y= -2;y<top;y++)
        {
            if(cave>=0&&y>=0&&(float)y<math::ceil(ceiling+0.1f))continue;
            (void)vpt::set_voxel(x,y,z,surface_color((float)x+0.5f,(float)y+0.5f,(float)z+0.5f,seed));
        }
    }
    vpt::finish_edit();
    game_room_count=SURFACE_STOPS;game_door_count=0;game_item_count=0;
    for(int i=0;i<SURFACE_STOPS;i++)
    {
        Vec p=surface_stop(i,seed);game_rooms[i]={p[0]-7,p[2]-7,p[0]+7,p[2]+7,i==0?1:0};
        if(i==0) { grig(ROBOT_RIGS[vpt::clampi(player_robot,0,ROBOT_COUNT-1)],p[0],p[2],1,false);continue; }
        if(i==6) { grig("dune-stalker",p[0],p[2],1.05f,false);continue; }
        for(int s=0;s<3;s++) { float a=grand()*6.283f;grig("ash-scavenger",p[0]+math::cos(a)*3,p[2]+math::sin(a)*3,grange(0.85f,1.15f),false); }
        if(i%2==0)grig("dune-stalker",p[0]+3.5f,p[2]-1,1,false);
        // Landmark on the trail side AWAY from any side-cave mouth (caves sit outward of stops 2/4/6).
        Vec out=vpt::normalized((Vec){p[0],0,p[2]});float ox=-out[0]*3.2f-out[2]*1.6f;float oz=-out[2]*3.2f+out[0]*1.6f;
        surface_prop(i%2==0?"skull-fossil":"bone-ribs",p[0]+ox,p[2]+oz,grange(0.9f,1.3f),grand()*6.283f);
    }
    const ZString[9] PROPS={"pitted-boulder-a","shale-shards","husk-tree","bristle-shrub-a","thornbush-a","tumbleweed","bone-ribs","pod-succulent","hoodoo"};
    for(int i=0;i<175;i++)
    {
        float x=grange(-49,49);float z=grange(-49,49);float trail=surface_trail(x,z,seed);
        if(trail<2.8f||surface_height(x,z,seed)>2)continue;
        bool mouth=false;for(int c=0;c<3;c++)if(surface_cave_open(c,x,z)> -2.5f)mouth=true;
        if(mouth)continue;   // keep every cave entrance cut clear of boulders/hoodoos
        surface_prop(PROPS[gint(0,8)],x,z,grange(0.65f,1.6f),grand()*6.283f);
    }
    // A dead field station. No scattered supply crates: the layer has exactly ONE crate (salvage den, below).
    gmachine("diesel-generator",surface_stop(3,seed)[0]+4,surface_stop(3,seed)[2]+3,0.7f);
    Vec exit={};
    for(int i=0;i<3;i++)
    {
        SurfaceCave c=surface_caves[i];game_rooms[game_room_count++]={c.center[0]-c.radius,c.center[2]-c.radius,c.center[0]+c.radius,c.center[2]+c.radius,c.content==2?3:0};
        if(c.content==2)
        {
            exit=c.center;grig("alien-crawler",exit[0],exit[2],1.6f,false);
            for(int s= -1;s<=1;s+=2)grig("alien-nest",exit[0]+(float)s*3.5f,exit[2]+1.5f,1,true);
            for(int s=0;s<3;s++)grig("alien-skitter",exit[0]+grange(-2,2),exit[2]+grange(-2,2),grange(0.85f,1.1f),false);
            grig("alien-flutter",exit[0]+1,exit[2]-1,1,false);
        }
        else if(c.content==1) { for(int s=0;s<3;s++)grig(s==0?"dune-stalker":"ash-scavenger",c.center[0]+grange(-2,2),c.center[2]+grange(-2,2),1,false); }
        else
        {
            // The salvage den (always exactly one): one crate, opened with E, holding one modifier.
            int crate=vpt::instance_count;gmachine("service-crate",c.center[0],c.center[2],grand()*6.283f);
            if(vpt::instance_count>crate) { vpt::instances[crate].y=0.12f;game_items[game_item_count++]={c.center[0],c.center[2],gint(1,8),true}; }
        }
    }
    int arch=vpt::import_asset("assets/library/BLACK_START/rift-monument.vpt.json");
    if(arch>=0)vpt::instances[vpt::instance_count++]={arch,exit[0],0.12f,exit[2]-3,0,1,0};
    if(detailed&&!bake_surface_detail(seed))return false;
    if(!detailed)vpt::make_props_unique();
    for(int r=0;r<vpt::rig_count;r++)vpt::rigs[r].y=surface_walk_height(vpt::rigs[r].x,vpt::rigs[r].z);
    if(detailed)attach_nests(true);
    vpt::update_rigs(1.0f/60);vpt::finish_edit();vpt::scene_open=true;vpt::scene_dirty=true;
    vpt::report(rl::text_format("Generated SURFACE layer 0 (seed %u): open ash/salt badlands, %d creatures/robot, %d instances, atlas %.1fM voxels.",seed,vpt::rig_count,vpt::instance_count,(double)(vpt::active_asset_pixels()+vpt::chunk_count*vpt::CHUNK_VOXELS)/1e6));
    return vpt::rig_count>0;
}
fn bool generate_layer(uint seed,int layer,bool detailed=true) => layer==0?generate_surface(seed,detailed):layer== -1?generate_depths(seed,detailed):false;
