module depths;
import std::math;
import raylib6::rl;
import vpt;

// Minimap: starts blank and fills in what the robot has seen (fog of war). Every 0.15 s the cells within
// MAP_REVEAL metres that are in line of sight (2D, through open cells) become explored; walls next to them
// draw as the cave outline. One texel per 1 m cell, redrawn into a texture only when something new is seen.

const int MAP_MAX=256;const float MAP_REVEAL=12;const int MAP_PX=220;
bool[MAP_MAX*MAP_MAX] map_seen;bool map_dirty;float map_timer;
rl::RLTexture2D map_tex;uint* map_pixels;int map_n;

fn void minimap_reset()
{
    map_seen={};map_dirty=true;map_timer=0;map_n=math::min(vpt::world_size,MAP_MAX);
}
fn bool map_open(int x,int z) => vpt::voxel(x,0,z)==0&&vpt::voxel(x,-1,z)!=0;
fn void minimap_update(float dt)
{
    if(player<0||player>=vpt::rig_count)return;
    map_timer-=dt;if(map_timer>0)return;map_timer=0.15f;
    vpt::Rig* me=&vpt::rigs[player];int half=vpt::world_size/2;
    int px=(int)math::floor(me.x);int pz=(int)math::floor(me.z);int r=(int)MAP_REVEAL;
    for(int dz= -r;dz<=r;dz++)for(int dx= -r;dx<=r;dx++)
    {
        if(dx*dx+dz*dz>r*r)continue;int x=px+dx;int z=pz+dz;
        int ix=x+half;int iz=z+half;if(ix<0||iz<0||ix>=map_n||iz>=map_n||map_seen[iz*MAP_MAX+ix])continue;
        // walk the line from the robot: visible if nothing but open cells lie in between
        int steps=math::max(math::abs(dx),math::abs(dz));bool clear=true;
        for(int s=1;s<steps;s++) { int qx=px+(int)math::round((float)dx*(float)s/(float)steps);int qz=pz+(int)math::round((float)dz*(float)s/(float)steps);if(!map_open(qx,qz)) { clear=false;break; } }
        if(clear) { map_seen[iz*MAP_MAX+ix]=true;map_dirty=true; }
    }
}
fn void minimap_draw(rl::RLRectangle view)
{
    if(player<0||player>=vpt::rig_count||map_n<=0)return;
    int half=vpt::world_size/2;
    if(!map_tex.id||map_tex.width!=map_n)
    {
        if(map_tex.id)rl::unload_texture(map_tex);if(map_pixels)rl::mem_free(map_pixels);
        map_pixels=(uint*)rl::mem_alloc((uint)(map_n*map_n*4));
        rl::RLImage img={map_pixels,map_n,map_n,1,rl::RLPixelFormat.UNCOMPRESSED_R8G8B8A8};for(int i=0;i<map_n*map_n;i++)map_pixels[i]=0;
        map_tex=rl::load_texture_from_image(img);map_tex.set_filter(rl::RLTextureFilter.POINT);map_dirty=true;
    }
    if(map_dirty)
    {
        for(int z=0;z<map_n;z++)for(int x=0;x<map_n;x++)
        {
            uint c=0;
            if(map_seen[z*MAP_MAX+x]) { c=map_open(x-half,z-half)?vpt::rgba(70,64,58,235):vpt::rgba(150,128,96,245); }
            else
            {
                // unseen rock right next to a seen floor cell: the cave wall outline
                bool edge=false;if(!map_open(x-half,z-half))for(int k=0;k<4&&!edge;k++) { int nx=x+(k==0?1:k==1?-1:0);int nz=z+(k==2?1:k==3?-1:0);if(nx>=0&&nz>=0&&nx<map_n&&nz<map_n&&map_seen[nz*MAP_MAX+nx]&&map_open(nx-half,nz-half))edge=true; }
                if(edge)c=vpt::rgba(150,128,96,245);
            }
            map_pixels[z*map_n+x]=c;
        }
        map_tex.update(map_pixels);map_dirty=false;
    }
    float s=(float)MAP_PX;float x0=view.x+view.width-s-16;float y0=view.y+16;
    rl::draw_rectangle_rounded({x0-6,y0-6,s+12,s+12},0.06f,6,{20,22,23,170});
    // world +z is "down" on the map so it matches the default top-down camera (orbit 0.68 is close enough)
    rl::draw_texture_pro(map_tex,{0,0,(float)map_n,(float)map_n},{x0,y0,s,s},{0,0},0,rl::WHITE);
    float k=s/(float)map_n;
    // shop door + seen keys
    if(shop_room>=0)
    {
        Vec d=shop_door_pos();int ix=(int)d[0]+half;int iz=(int)d[2]+half;
        if(ix>=0&&iz>=0&&ix<map_n&&iz<map_n&&(map_seen[iz*MAP_MAX+ix]||shop_unlocked))
        { rl::draw_rectangle((int)(x0+(d[0]+(float)half)*k)-3,(int)(y0+(d[2]+(float)half)*k)-3,7,7,shop_unlocked?(rl::RLColor){80,220,90,255}:(rl::RLColor){235,60,50,255}); }
    }
    for(int i=0;i<pickup_count;i++)if(!pickups[i].taken&&pickups[i].kind==KEY_KIND)
    {
        int ix=(int)pickups[i].x+half;int iz=(int)pickups[i].z+half;
        if(ix>=0&&iz>=0&&ix<map_n&&iz<map_n&&map_seen[iz*MAP_MAX+ix])rl::draw_circle((int)(x0+(pickups[i].x+(float)half)*k),(int)(y0+(pickups[i].z+(float)half)*k),3,{255,200,40,255});
    }
    if(portal_exists&&layer_clear)
    {
        int px=(int)(x0+(portal_base[0]+(float)half)*k);int pz=(int)(y0+(portal_base[2]+(float)half)*k);
        rl::draw_circle_lines(px,pz,5,{110,230,255,255});rl::draw_circle(px,pz,2,{216,142,255,255});
    }
    // the robot: an arrow along its facing
    vpt::Rig* me=&vpt::rigs[player];float cx=x0+(me.x+(float)half)*k;float cy=y0+(me.z+(float)half)*k;
    float fy=third_person?tp_yaw:me.yaw;rl::RLVector2 f={math::sin(fy),math::cos(fy)};rl::RLVector2 sd={-f[1],f[0]};
    rl::draw_triangle({cx+f[0]*8,cy+f[1]*8},{cx-f[0]*5-sd[0]*5,cy-f[1]*5-sd[1]*5},{cx-f[0]*5+sd[0]*5,cy-f[1]*5+sd[1]*5},{250,189,47,255});
    rl::draw_triangle({cx+f[0]*8,cy+f[1]*8},{cx-f[0]*5+sd[0]*5,cy-f[1]*5+sd[1]*5},{cx-f[0]*5-sd[0]*5,cy-f[1]*5-sd[1]*5},{250,189,47,255});
}
