module depths;
import std::math;
import raylib6::rl;
import vpt;

// Procedural "Depths" layer, generated in the engine (port of assets/scenes/build-depths.py, which stays as
// the reference for the fixed depths-1 scene). Isaac-style floor plan: rooms grow from the start room on a
// 7x7 grid of 16 m cells; dead ends become the boss / treasure rooms; a couple of rooms merge into halls.
// Rooms are carved out of 4 m tall rock (1 m terrain voxels) with varied shapes and joined by doorways.
//
// detailed=true adds the fine voxel layer (bake_cave_detail): unique sculpted rock per 4 m block (0.125 m
// voxels) and unique floor slabs (0.05 m voxels, same detail as the wastes ground assets). The 1 m terrain
// stays underneath as the collision / gameplay world, fully enclosed by the detail so it is never seen.
//
// Saved scenes store only {seed, detailed}: generated assets have no file and are re-baked on load.

const int GEN_SIZE=128;
const int GEN_CELL=16;
const int GEN_GRID=7;
const float GEN_ORIGIN= -56;    // grid spans -56..56
const int GEN_ROCK_TOP=4;       // rock voxels y = 0..3
// Terrain/cave quality decisions keep the original 16M atlas budget; the rest is room for carvable prop copies.
const int GEN_ATLAS_BUDGET=16777216;
const ZString GEN_LIB="assets/library/BLACK_START/";

uint gen_seed;bool gen_detailed;bool gen_active;int gen_cap_quality;bool gen_roof_fine;int gen_roof_mode;   // 0 full, 1 far rock tops coarse, 2 all rock tops coarse   // the open scene came from the generator (saved as its seed)

uint gen_rng=1;
fn float grand() { gen_rng^=gen_rng<<13;gen_rng^=gen_rng>>17;gen_rng^=gen_rng<<5;return (float)(gen_rng&0xffffff)/16777216.0f; }
fn float grange(float a,float b) => a+(b-a)*grand();
fn int gint(int a,int b) => a+(int)(grand()*(float)(b-a+1)*0.99999f);   // inclusive

// ---------------------------------------------------------------- floor plan
struct GenCell { int x;int z; }
bool[GEN_GRID][GEN_GRID] g_room;int[GEN_GRID][GEN_GRID] g_dist;int[GEN_GRID][GEN_GRID] g_group;
GenCell g_start;GenCell g_boss;GenCell g_treasure;GenCell g_shop;
const int[4] DX={1,-1,0,0};const int[4] DZ={0,0,1,-1};
fn bool gin(int x,int z) => x>=0&&z>=0&&x<GEN_GRID&&z<GEN_GRID;
fn bool groom(int x,int z) => gin(x,z)&&g_room[x][z];
fn int glinks(int x,int z) { int n=0;for(int d=0;d<4;d++)if(groom(x+DX[d],z+DZ[d]))n++;return n; }

fn void gen_plan()
{
    while(true)
    {
        for(int x=0;x<GEN_GRID;x++)for(int z=0;z<GEN_GRID;z++) { g_room[x][z]=false;g_dist[x][z]=0; }
        g_start={GEN_GRID/2,GEN_GRID/2};g_room[g_start.x][g_start.z]=true;int count=1;int target=gint(9,12);
        GenCell[64] queue;int head=0;int tail=0;queue[tail++]=g_start;
        while(head<tail&&count<target)
        {
            GenCell c=queue[head++];
            for(int d=0;d<4;d++)
            {
                int nx=c.x+DX[d];int nz=c.z+DZ[d];
                if(!gin(nx,nz)||g_room[nx][nz]||count>=target)continue;
                if(glinks(nx,nz)>1)continue;
                if(grand()<0.5f)continue;
                g_room[nx][nz]=true;count++;g_dist[nx][nz]=g_dist[c.x][c.z]+1;if(tail<64)queue[tail++]={nx,nz};
            }
            if(head>=tail&&count<target)
            {
                int pick=gint(0,count-1);
                for(int x=0;x<GEN_GRID;x++)for(int z=0;z<GEN_GRID;z++)if(g_room[x][z]&&pick--==0) { head=0;tail=0;queue[tail++]={x,z}; }
            }
        }
        // dead ends, farthest first
        GenCell[64] ends;int end_count=0;
        for(int x=0;x<GEN_GRID;x++)for(int z=0;z<GEN_GRID;z++)if(g_room[x][z]&&glinks(x,z)==1&&!(x==g_start.x&&z==g_start.z))ends[end_count++]={x,z};
        for(int i=0;i<end_count;i++)for(int j=i+1;j<end_count;j++)if(g_dist[ends[j].x][ends[j].z]>g_dist[ends[i].x][ends[i].z]) { GenCell t=ends[i];ends[i]=ends[j];ends[j]=t; }
        if(count<9||end_count<3)continue;
        if(math::abs(ends[0].x-g_start.x)+math::abs(ends[0].z-g_start.z)==1)continue;
        g_boss=ends[0];g_treasure=ends[1];g_shop=ends[2];return;
    }
}

// ---------------------------------------------------------------- rooms
const int SH_HALL=0;const int SH_CAVERN=1;const int SH_PILLARS=2;const int SH_RING=3;const int SH_CROSS=4;const int SH_RIDGES=5;
struct GenRoom { float x0;float z0;float x1;float z1;int kind;int shape;int cells;float[18] feature;int features; }
GenRoom[64] g_rooms;int g_room_count;int[GEN_GRID][GEN_GRID] g_room_of;

fn bool gen_open_floor(GenRoom* r,float x,float z)
{
    float m=1.6f;
    if(!(r.x0+m<=x&&x<=r.x1-m&&r.z0+m<=z&&z<=r.z1-m))return false;
    float cx=(r.x0+r.x1)/2;float cz=(r.z0+r.z1)/2;float hx=(r.x1-r.x0)/2-m;float hz=(r.z1-r.z0)/2-m;
    float u=(x-cx)/hx;float v=(z-cz)/hz;
    float wob=(vpt::vnoise(x*0.35f,z*0.35f,gen_seed+1)-0.5f)*0.22f;
    switch(r.shape)
    {
        case SH_HALL:
            float rr=0.35f;float du=math::max(math::abs(u)-(1-rr),0.0f);float dv=math::max(math::abs(v)-(1-rr),0.0f);
            return du*du+dv*dv<=rr*rr*(1+wob);
        case SH_CAVERN:
            float ang=math::atan2(v,u);float rad=0.84f+(vpt::vnoise(math::cos(ang)*2+9,math::sin(ang)*2,gen_seed+2)-0.5f)*0.45f;
            return u*u+v*v<=rad*rad;
        case SH_PILLARS:
            for(int k=0;k<r.features;k+=3) { float px=r.feature[k];float pz=r.feature[k+1];float pr=r.feature[k+2];if((x-px)*(x-px)+(z-pz)*(z-pz)<pr*pr)return false; }
            return math::abs(u)<=0.96f+wob*0.2f&&math::abs(v)<=0.96f+wob*0.2f;
        case SH_RING:
            if((x-cx)*(x-cx)+(z-cz)*(z-cz)<r.feature[0]*r.feature[0]*(1+wob))return false;
            return u*u+v*v<=1.0f+wob;
        case SH_CROSS:
            return (math::abs(u)<=0.36f+wob||math::abs(v)<=0.36f+wob)&&math::abs(u)<=0.98f&&math::abs(v)<=0.98f;
        case SH_RIDGES:
            float ca=r.feature[0];float sa=r.feature[1];float off=r.feature[2];
            float t=(x-cx)*ca+(z-cz)*sa;float along= -(x-cx)*sa+(z-cz)*ca;
            for(int k= -1;k<=1;k++)if(math::abs(t-(float)k*4.2f-off)<0.7f&&!(math::abs(along-(float)k*2.5f)<1.8f))return false;
            return math::abs(u)<=0.97f&&math::abs(v)<=0.97f;
    }
    return false;
}
fn bool gen_in_passage(float x,float z)
{
    if(in_corridor(x,z))return true;
    for(int k=0;k<game_door_count;k++)
    {
        GameDoorFile d=game_doors[k];
        if(d.axis==0&&math::abs(z-d.z)<1.9f&&math::abs(x-d.x)<5.2f)return true;
        if(d.axis==1&&math::abs(x-d.x)<1.9f&&math::abs(z-d.z)<5.2f)return true;
    }
    return false;
}
fn bool gen_is_open(float x,float z)
{
    int cx=(int)math::floor((x-GEN_ORIGIN)/GEN_CELL);int cz=(int)math::floor((z-GEN_ORIGIN)/GEN_CELL);
    if(gin(cx,cz)&&g_room[cx][cz]&&gen_open_floor(&g_rooms[g_room_of[cx][cz]],x,z))return true;
    return gen_in_passage(x,z);
}

// ---------------------------------------------------------------- organic layout
// Natural caves: blob chambers (stretched, rotated, wobbly rim, rock pillars in the big ones) joined by winding
// tunnels of varying width (some squeezes). A spanning tree + a couple of loops; the boss sits at the far end,
// the shop is the one built room: a square chamber at a dead end, entered through a short straight corridor
// where its door sits (the game draws the door + LEDs there).
struct Chamber { float x;float z;float rx;float rz;float ang;float r;int kind;int parent;int deg; }
struct Tunnel { float[40] px;float[40] pz;float[40] w;int n;float x0;float z0;float x1;float z1; }
Chamber[16] ch;int ch_count;Tunnel[24] tun;int tun_count;
int shop_ch= -1;float shop_cx;float shop_cz;const float SHOP_HALF=6;
float cor_x0;float cor_z0;float cor_x1;float cor_z1;float door_x;float door_z;int door_axis;

fn void add_tunnel(float ax,float az,float bx,float bz,bool squeeze_ok)
{
    if(tun_count>=24)return;Tunnel* t=&tun[tun_count++];
    float dx=bx-ax;float dz=bz-az;float l=math::sqrt(dx*dx+dz*dz);float px= -dz/l;float pz=dx/l;
    t.n=vpt::clampi((int)(l/2.2f)+1,4,39)+1;float amp=math::min(l*0.18f,7.0f)*grange(0.35f,1);float freq=grange(1,2.4f);float ph=grange(0,6.28f);
    float base=grange(1.5f,2.0f);float sq=squeeze_ok&&grand()<0.45f?grange(0.3f,0.7f):-9;uint s=(uint)(grand()*9999);   // half-widths; the fine rock skin overhangs the collision by 0.1-0.6 m per side
    t.x0=1e9f;t.z0=1e9f;t.x1= -1e9f;t.z1= -1e9f;
    for(int i=0;i<t.n;i++)
    {
        float u=(float)i/(float)(t.n-1);float env=math::sin(u*3.14159f);
        float off=amp*env*math::sin(u*3.14159f*freq+ph)+(vpt::vnoise(u*5,0.5f,s)-0.5f)*1.6f*env;
        t.px[i]=ax+dx*u+px*off;t.pz[i]=az+dz*u+pz*off;
        float w=base+(vpt::vnoise(u*4+3,1.5f,s+1)-0.5f)*0.9f;if(sq> -1)w-=0.7f*math::exp(-(u-sq)*(u-sq)/0.004f);
        t.w[i]=math::max(w,1.3f);   // squeezes >= 2.6 m between collision walls (was 2.1: bodies visibly clipped the rock)
        t.x0=math::min(t.x0,t.px[i]-t.w[i]);t.z0=math::min(t.z0,t.pz[i]-t.w[i]);t.x1=math::max(t.x1,t.px[i]+t.w[i]);t.z1=math::max(t.z1,t.pz[i]+t.w[i]);
    }
}
fn bool in_tunnel(Tunnel* t,float x,float z)
{
    if(x<t.x0||x>t.x1||z<t.z0||z>t.z1)return false;
    for(int i=0;i+1<t.n;i++)
    {
        float ax=t.px[i];float az=t.pz[i];float bx=t.px[i+1];float bz=t.pz[i+1];float ex=bx-ax;float ez=bz-az;float ll=ex*ex+ez*ez;
        float u=ll>0?vpt::clampf(((x-ax)*ex+(z-az)*ez)/ll,0,1):0;float qx=ax+ex*u-x;float qz=az+ez*u-z;float w=vpt::mixf(t.w[i],t.w[i+1],u);
        if(qx*qx+qz*qz<w*w)return true;
    }
    return false;
}
fn bool in_shop_zone(float x,float z) => math::abs(x-shop_cx)<SHOP_HALF+1.5f&&math::abs(z-shop_cz)<SHOP_HALF+1.5f;
fn bool in_corridor(float x,float z) => shop_ch>=0&&x>=cor_x0&&x<=cor_x1&&z>=cor_z0&&z<=cor_z1;
fn bool org_open(float x,float z)
{
    if(math::abs(x)>58||math::abs(z)>58)return false;
    if(shop_ch>=0)
    {
        if(math::abs(x-shop_cx)<SHOP_HALF-0.8f&&math::abs(z-shop_cz)<SHOP_HALF-0.8f)return true;
        if(in_corridor(x,z))return true;
        if(in_shop_zone(x,z))return false;   // the shop is walled: nothing else breaks into it
    }
    for(int i=0;i<ch_count;i++)
    {
        Chamber* c=&ch[i];if(c.kind==4)continue;float dx=x-c.x;float dz=z-c.z;
        if(math::abs(dx)>c.r*1.6f||math::abs(dz)>c.r*1.6f)continue;
        float co=math::cos(c.ang);float si=math::sin(c.ang);float u=(dx*co+dz*si)/c.rx;float v=(-dx*si+dz*co)/c.rz;
        float a=math::atan2(v,u);float d=math::sqrt(u*u+v*v);
        float wob=(vpt::vnoise(math::cos(a)*1.6f+(float)i*7,math::sin(a)*1.6f,gen_seed+80)-0.5f)*0.55f+(vpt::vnoise(x*0.25f,z*0.25f,gen_seed+81)-0.5f)*0.25f;
        if(d<1+wob)
        {
            if(c.r>6.5f&&d>0.3f&&d<0.78f&&vpt::vnoise(x*0.33f,z*0.33f,gen_seed+82)>0.79f)return false;   // rock pillars
            return true;
        }
    }
    for(int i=0;i<tun_count;i++)if(in_tunnel(&tun[i],x,z))return true;
    return false;
}
fn void gen_organic()
{
    while(true)
    {
        ch_count=0;tun_count=0;shop_ch= -1;
        int target=gint(8,10);
        for(int tries=0;tries<600&&ch_count<target;tries++)
        {
            float r=ch_count==0?grange(7.5f,8.5f):grange(5.5f,9.5f);float x=ch_count==0?grange(-10,10):grange(-40,40);float z=ch_count==0?grange(-10,10):grange(-40,40);
            bool ok=true;for(int i=0;i<ch_count;i++) { float dx=x-ch[i].x;float dz=z-ch[i].z;if(math::sqrt(dx*dx+dz*dz)<r+ch[i].r+5)ok=false; }
            if(!ok)continue;
            float e=grange(0.78f,1.3f);ch[ch_count++]={x,z,r*e,r/e,grange(0,3.14159f),r,0,-1,0};
        }
        if(ch_count<8)continue;
        // spanning tree (Prim) rooted at the start chamber
        bool[16] in;in[0]=true;float[16] path;path[0]=0;
        for(int k=1;k<ch_count;k++)
        {
            int bi= -1;int bj= -1;float bd=1e9f;
            for(int i=0;i<ch_count;i++)if(in[i])for(int j=0;j<ch_count;j++)if(!in[j]) { float dx=ch[i].x-ch[j].x;float dz=ch[i].z-ch[j].z;float d=math::sqrt(dx*dx+dz*dz);if(d<bd) { bd=d;bi=i;bj=j; } }
            in[bj]=true;ch[bj].parent=bi;ch[bi].deg++;ch[bj].deg++;path[bj]=path[bi]+bd;
        }
        int boss= -1;float far= -1;for(int i=1;i<ch_count;i++)if(ch[i].deg==1&&path[i]>far) { far=path[i];boss=i; }
        int shop= -1;int treasure= -1;
        for(int i=1;i<ch_count;i++)if(ch[i].deg==1&&i!=boss) { if(shop<0) { shop=i; } else if(treasure<0) { treasure=i; } }
        if(boss<0||shop<0)continue;
        if(treasure<0)for(int i=1;i<ch_count;i++)if(i!=boss&&i!=shop) { treasure=i;break; }
        ch[0].kind=1;ch[boss].kind=3;ch[shop].kind=4;if(treasure>0)ch[treasure].kind=2;
        ch[boss].rx*=1.25f;ch[boss].rz*=1.25f;ch[boss].r*=1.25f;
        // the shop: a square room, door on the side facing its parent, a straight corridor out
        shop_ch=shop;shop_cx=ch[shop].x;shop_cz=ch[shop].z;Chamber* p=&ch[ch[shop].parent];
        float vx=p.x-shop_cx;float vz=p.z-shop_cz;float ex;float ez;
        if(math::abs(vx)>=math::abs(vz))
        {
            float s=vx>0?1:-1;door_axis=0;door_x=shop_cx+s*SHOP_HALF;door_z=shop_cz;ex=shop_cx+s*(SHOP_HALF+4);ez=shop_cz;
            cor_x0=math::min(shop_cx+s*(SHOP_HALF-1),ex);cor_x1=math::max(shop_cx+s*(SHOP_HALF-1),ex);cor_z0=shop_cz-1.85f;cor_z1=shop_cz+1.85f;
        }
        else
        {
            float s=vz>0?1:-1;door_axis=1;door_z=shop_cz+s*SHOP_HALF;door_x=shop_cx;ez=shop_cz+s*(SHOP_HALF+4);ex=shop_cx;
            cor_z0=math::min(shop_cz+s*(SHOP_HALF-1),ez);cor_z1=math::max(shop_cz+s*(SHOP_HALF-1),ez);cor_x0=shop_cx-1.85f;cor_x1=shop_cx+1.85f;
        }
        // tunnels: tree edges + up to two loops; nothing but the shop's own tunnel may pass near the shop
        for(int i=1;i<ch_count;i++)
        {
            Chamber* c=&ch[i];Chamber* q=&ch[c.parent];
            if(i==shop) { add_tunnel(ex,ez,q.x,q.z,false); } else { add_tunnel(c.x,c.z,q.x,q.z,true); }
        }
        int loops=0;
        for(int i=0;i<ch_count&&loops<2;i++)for(int j=i+1;j<ch_count&&loops<2;j++)
        {
            if(i==shop||j==shop||ch[i].parent==j||ch[j].parent==i)continue;
            float dx=ch[i].x-ch[j].x;float dz=ch[i].z-ch[j].z;if(math::sqrt(dx*dx+dz*dz)>30||grand()<0.5f)continue;
            add_tunnel(ch[i].x,ch[i].z,ch[j].x,ch[j].z,true);loops++;
        }
        bool clash=false;int shop_tunnel=shop-1;
        for(int t=0;t<tun_count&&!clash;t++)if(t!=shop_tunnel)for(int i=0;i<tun[t].n;i++)if(in_shop_zone(tun[t].px[i],tun[t].pz[i])) { clash=true;break; }
        for(int i=0;i<ch_count&&!clash;i++)if(i!=shop&&math::abs(ch[i].x-shop_cx)<ch[i].r+SHOP_HALF+1.5f&&math::abs(ch[i].z-shop_cz)<ch[i].r+SHOP_HALF+1.5f)clash=true;
        if(clash)continue;
        return;
    }
}
// Rooms (bounding boxes + kinds, for spawning) and the shop door.
fn void gen_organic_rooms()
{
    g_room_count=0;game_room_count=0;game_door_count=0;game_item_count=0;int shop_room_index= -1;int parent_room= -1;
    for(int i=0;i<ch_count;i++)
    {
        Chamber c=ch[i];float e=c.kind==4?SHOP_HALF:math::max(c.rx,c.rz)*1.15f;
        GenRoom r={.x0=c.x-e,.z0=c.z-e,.x1=c.x+e,.z1=c.z+e,.kind=c.kind,.cells=c.r>7?2:1};
        if(i==shop_ch)shop_room_index=g_room_count;
        g_rooms[g_room_count++]=r;game_rooms[game_room_count++]={r.x0,r.z0,r.x1,r.z1,r.kind};
    }
    if(shop_ch>=0) { parent_room=ch[shop_ch].parent;game_doors[game_door_count++]={door_x,door_z,door_axis,shop_room_index,parent_room}; }
}

// ---------------------------------------------------------------- contents
struct Occupied { float x;float z;float r; }
Occupied[256] g_occ;int g_occ_count;
fn bool gopen(float x,float z) { int ix=(int)math::floor(x);int iz=(int)math::floor(z);return vpt::voxel(ix,0,iz)==0&&vpt::voxel(ix,-1,iz)!=0; }
fn bool gfree(float x,float z,float r)
{
    if(!gopen(x,z)||gen_in_passage(x,z))return false;
    for(int i= -1;i<=1;i++)for(int j= -1;j<=1;j++)if(!gopen(x+(float)i*r,z+(float)j*r))return false;
    for(int k=0;k<g_occ_count;k++) { Occupied o=g_occ[k];if(math::sqrt((x-o.x)*(x-o.x)+(z-o.z)*(z-o.z))<=r+o.r)return false; }
    return true;
}
fn void goccupy(float x,float z,float r) { if(g_occ_count<256)g_occ[g_occ_count++]={x,z,r}; }
fn bool gspot(GenRoom* g,float r,float* ox,float* oz)
{
    for(int t=0;t<80;t++)
    {
        float x=grange(g.x0+2,g.x1-2);float z=grange(g.z0+2,g.z1-2);
        if(gfree(x,z,r)) { goccupy(x,z,r);*ox=x;*oz=z;return true; }
    }
    return false;
}
// Nests sit against a wall: walk from a free interior point towards the nearest rock.
fn bool gwall_spot(GenRoom* g,float* ox,float* oz)
{
    float x;float z;if(!gspot(g,0.9f,&x,&z))return false;
    float best=1e9f;float bx=0;float bz=0;
    for(int a=0;a<360;a+=20)
    {
        float dx=math::cos((float)a*0.017453293f);float dz=math::sin((float)a*0.017453293f);
        for(int i=1;i<16;i++) { float t=(float)i*0.5f;if(!gopen(x+dx*t,z+dz*t)) { if(t<best) { best=t;bx=dx;bz=dz; }break; } }
    }
    if(best<1e8f) { x+=bx*math::max(best-1.1f,0.0f);z+=bz*math::max(best-1.1f,0.0f); }
    *ox=x;*oz=z;return true;
}
fn void gprop(ZString name,float x,float z,float scale)
{
    if(vpt::instance_count>=vpt::MAX_INSTANCES)return;
    int id=vpt::import_asset(rl::text_format("%swastes/%s.vpt.json",GEN_LIB,name));if(id<0)return;
    vpt::instances[vpt::instance_count++]={id,x,0,z,grand()*6.2831853f,scale,0};
}
fn void gmachine(ZString name,float x,float z,float rotation)
{
    if(vpt::instance_count>=vpt::MAX_INSTANCES)return;
    int id=vpt::import_asset(rl::text_format("%s%s.vpt.json",GEN_LIB,name));if(id<0)return;
    vpt::instances[vpt::instance_count++]={id,x,0,z,rotation,1,0};
}
fn void grig(ZString name,float x,float z,float scale,bool seeded)
{
    if(vpt::rig_count>=40)return;
    int def=vpt::load_rig(rl::text_format("%s%s.rig.json",GEN_LIB,name));if(def<0)return;
    int r=vpt::spawn_rig(def,{x,0,z},grand()*6.2831853f,scale);
    if(r>=0&&seeded)vpt::rigs[r].shape_seed=(uint)(grand()*99998+1);
}

const ZString[11] GEN_PROPS={"pitted-boulder-a","pitted-boulder-b","shale-shards","crystal-shrub","bone-ribs","root-tangle","bulb-fungus-a","bulb-fungus-b","spore-stalks","thornbush-b","skull-fossil"};
const ZString[5] GEN_COVER={"ground-crust-a","ground-crust-b","ground-gravel","ground-ash-ripples","ground-salt"};

// Builds a whole new scene. Returns false (scene left empty) only if an asset/rig file is missing.
fn bool generate_depths(uint seed,bool detailed)
{
    vpt::new_scene(GEN_SIZE);vpt::release_assets();
    gen_seed=seed;gen_detailed=detailed;gen_active=true;gen_rng=seed*2654435761u|1;for(int i=0;i<8;i++)grand();
    vpt::lighting={200,37.32f,0,1.05f,0,1,0.988f,1,3,1,0,0};   // the user's depths lighting (night, sky fill) minus the sun/moon: no sun shadow rays at all
    gen_organic();gen_organic_rooms();
    // carve: floor (y -2..-1) everywhere, rock (y 0..3) where nothing is open
    int half=GEN_SIZE/2;
    for(int x= -half;x<half;x++)for(int z= -half;z<half;z++)
    {
        float fx=(float)x+0.5f;float fz=(float)z+0.5f;bool opened=org_open(fx,fz);
        float a=vpt::vnoise((float)x*0.07f,(float)z*0.07f,seed+3);float r=vpt::vnoise((float)x*0.11f+5,(float)z*0.11f,seed+4);
        float[3] fl={38+a*20,34+a*17,31+a*15};if(r>0.7f) { fl[0]+=(r-0.7f)*90;fl[1]+=8; }
        for(int y= -2;y<=-1;y++) { float k=y==-2?0.75f:1;(void)vpt::set_voxel(x,y,z,vpt::rgba(vpt::clampi((int)(fl[0]*k),0,255),vpt::clampi((int)(fl[1]*k),0,255),vpt::clampi((int)(fl[2]*k),0,255))); }
        if(opened)continue;
        for(int y=0;y<GEN_ROCK_TOP;y++)
        {
            // crust strata: dark basalt bands, a rust seam, pale tuff at the top edge
            float band=vpt::vnoise((float)x*0.05f,(float)y*0.9f+(float)z*0.05f,seed+5);
            float[3] base=band<0.55f?(float[3]){44,40,37}:band<0.8f?(float[3]){58,49,41}:(float[3]){92,58,38};
            float k=0.78f+0.08f*(float)y+(vpt::vnoise((float)x*0.4f+(float)y,(float)z*0.4f,seed+6)-0.5f)*0.12f;
            if(y==GEN_ROCK_TOP-1) { base[0]+=10;base[1]+=9;base[2]+=8; }
            (void)vpt::set_voxel(x,y,z,vpt::rgba(vpt::clampi((int)(base[0]*k),0,255),vpt::clampi((int)(base[1]*k),0,255),vpt::clampi((int)(base[2]*k),0,255)));
        }
    }
    vpt::finish_edit();
    // contents
    g_occ_count=0;
    for(int i=0;i<g_room_count;i++)
    {
        GenRoom* g=&g_rooms[i];float cx=(g.x0+g.x1)/2;float cz=(g.z0+g.z1)/2;bool big=g.cells>1;float x;float z;
        for(int n=gint(2,4)*(big?2:1);n>0;n--)if(gspot(g,1.2f,&x,&z))gprop(GEN_COVER[gint(0,4)],x,z,grange(0.8f,1.2f));
        if(g.kind==1) { goccupy(cx,cz,2);int before=vpt::rig_count;grig(ROBOT_RIGS[vpt::clampi(player_robot,0,ROBOT_COUNT-1)],cx,cz,1,false);if(vpt::rig_count>before) { vpt::rigs[before].yaw=0;vpt::rigs[before].desired_yaw=0; }continue; }
        if(g.kind==4)
        {
            // Shop: the console in the middle (the game finds it at the room centre), machinery along the sides.
            goccupy(cx,cz,2.2f);gmachine("control-console",cx,cz,0);
            float hx=(g.x1-g.x0)/2-1.9f;float hz=(g.z1-g.z0)/2-1.9f;
            if(gfree(cx-hx,cz-hz,1.5f)) { gmachine("diesel-generator",cx-hx,cz-hz,0.6f);goccupy(cx-hx,cz-hz,1.6f); }
            if(gfree(cx+hx,cz-hz,1.0f)) { gmachine("service-crate",cx+hx,cz-hz,1.2f);goccupy(cx+hx,cz-hz,1); }
            if(gfree(cx+hx,cz+hz,1.0f)) { gmachine("diesel-tank",cx+hx,cz+hz,2.4f);goccupy(cx+hx,cz+hz,1); }
            if(gfree(cx-hx,cz+hz,0.6f)) { gmachine("work-lamp",cx-hx,cz+hz,0.3f);goccupy(cx-hx,cz+hz,0.6f); }
            continue;
        }
        // Small territorial cave-wings, separate from the ground-creature waves.
        if(g.kind!=3&&i%2==0)for(int f=0;f<2;f++)if(gspot(g,0.6f,&x,&z))grig("alien-flutter",x,z,grange(0.9f,1.05f),false);
        if(g.kind==2)
        {
            if(game_item_count<16&&grand()<0.6f)game_items[game_item_count++]={cx,cz,gint(1,8),false};goccupy(cx,cz,1.5f);   // kind = modifier index + 1
            for(int a=0;a<360;a+=72) { x=cx+math::cos((float)a*0.017453293f)*3;z=cz+math::sin((float)a*0.017453293f)*3;if(gfree(x,z,0.6f)) { gprop("crystal-shrub",x,z,grange(0.8f,1.1f));goccupy(x,z,0.6f); } }
            continue;
        }
        for(int n=gint(2,4)*(big?2:1);n>0;n--)if(gspot(g,0.9f,&x,&z))gprop(GEN_PROPS[gint(0,10)],x,z,grange(0.7f,1.2f));
        if(g.kind==3)
        {
            goccupy(cx,cz,2.5f);grig("alien-crawler",cx,cz,1.6f,false);
            for(int s=0;s<2;s++)if(gwall_spot(g,&x,&z))grig("alien-nest",x,z,1.1f,true);
            continue;
        }
        int wave=gint(0,4);   // 0 skitters, 1 crawler, 2 nest, 3 mixed, 4 bloaters
        if(wave==0||wave==3) { for(int n=wave==0?gint(3,5):2;n>0;n--)if(gspot(g,0.5f,&x,&z))grig("alien-skitter",x,z,grange(0.9f,1.2f),false); }
        if(wave==1||wave==3) { if(gspot(g,1.4f,&x,&z))grig("alien-crawler",x,z,1,false); }
        if(wave==4) { for(int n=gint(2,3)+(big?1:0);n>0;n--)if(gspot(g,0.8f,&x,&z))grig("alien-bloater",x,z,grange(0.9f,1.1f),false);
            if(gspot(g,0.5f,&x,&z))grig("alien-skitter",x,z,1,false); }
        else if(wave==3&&gint(0,1)==0) { if(gspot(g,0.8f,&x,&z))grig("alien-bloater",x,z,1,false); }
        if(wave==2||(wave==3&&big))
        {
            for(int n=1+(big?1:0);n>0;n--)if(gwall_spot(g,&x,&z))grig(grand()<0.3f?"alien-nest-spire":"alien-nest",x,z,1,true);
            if(gspot(g,0.5f,&x,&z))grig("alien-skitter",x,z,1,false);
        }
    }
    bool ok=vpt::rig_count>0;
    if(!detailed)vpt::make_props_unique();
    if(detailed&&!bake_cave_detail(seed))detailed=false;
    attach_nests(detailed);
    gen_detailed=detailed;
    vpt::update_rigs(1.0f/60);vpt::finish_edit();vpt::scene_open=true;vpt::scene_dirty=true;
    vpt::report(rl::text_format("Generated cave layer (seed %u%s%s%s): %d rooms, %d doors, %d creatures/robot, %d instances, atlas %.1fM of %.1fM voxels.",seed,detailed?", detailed voxels":"",detailed&&gen_roof_mode==2?", ROOF COARSER (0.25 m)":detailed&&gen_roof_mode==1?", roof over rock coarser":"",detailed&&gen_cap_quality>0?(gen_cap_quality==1?", far rock tops coarser":", rock tops coarser"):"",g_room_count,game_door_count,vpt::rig_count,vpt::instance_count,(double)(vpt::active_asset_pixels()+(vpt::terrain_hidden?0:vpt::chunk_count*vpt::CHUNK_VOXELS))/1e6,(double)vpt::MAX_ATLAS_PIXELS/1e6));
    return ok;
}

// Up in the corner where a wall meets the roof: find the wall, find the roof above it, then aim diagonally
// into the corner from inside the cave and sit there, facing out along the corner's bisector.
fn bool corner_nest(Rig* g,Vec base)
{
    float best=6;Pick wh;Vec wd;
    for(int a=0;a<16;a++) { Vec dir={math::cos((float)a*0.3927f),0,math::sin((float)a*0.3927f)};Pick h=vpt::world_pick({base+(Vec){0,2.6f,0},dir});if(h.hit&&h.distance<best) { best=h.distance;wh=h;wd=dir; } }
    if(best>=6)return false;
    Vec nw=wd*-1;Pick up=vpt::world_pick({wh.point+nw*1.2f,{0,1,0}});
    if(!up.hit||up.distance>5||up.instance<0||!vpt::assets[vpt::instances[up.instance].asset].roof)return false;
    Vec corner_dir=vpt::normalized(wd+(Vec){0,1,0});Vec from=(Vec){wh.point[0],up.point[1]-1.1f,wh.point[2]}+nw*1.1f;
    Pick c=vpt::world_pick({from,corner_dir});if(!c.hit||c.distance>3)return false;
    vpt::set_surface(g,vpt::normalized(nw+(Vec){0,-1,0}));g.x=c.point[0];g.y=c.point[1];g.z=c.point[2];g.yaw=grand()*6.28f;return true;
}
fn void attach_nests(bool roof)
{
    for(int r=0;r<vpt::rig_count;r++)
    {
        RigDef* d=&vpt::rig_defs[vpt::rigs[r].def];if(!d.anchor_count)continue;
        float u=grand();Rig* g=&vpt::rigs[r];Vec base={g.x,0,g.z};
        if(u<0.2f)continue;   // stays on the floor
        if(roof&&u>0.5f&&u<0.75f&&corner_nest(g,base))continue;
        if(roof&&u>=0.75f)
        {
            Pick h=vpt::world_pick({base+(Vec){0,1.0f,0},{0,1,0}});
            if(h.hit&&h.distance<7&&h.instance>=0&&vpt::assets[vpt::instances[h.instance].asset].roof)
            { Vec n=vpt::fitted_normal(h.point,{0,1,0},{0,-1,0});vpt::set_surface(g,n);g.x=h.point[0];g.y=h.point[1];g.z=h.point[2];g.yaw=grand()*6.28f;continue; }
        }
        float hy=grange(1.0f,2.4f);float best=5;Pick bh;Vec bd;
        for(int a=0;a<16;a++) { Vec dir={math::cos((float)a*0.3927f),0,math::sin((float)a*0.3927f)};Pick h=vpt::world_pick({base+(Vec){0,hy,0},dir});if(h.hit&&h.distance<best) { best=h.distance;bh=h;bd=dir; } }
        if(best<5) { Vec n=vpt::fitted_normal(bh.point,bd,bd*-1);n[1]=vpt::clampf(n[1],-0.3f,0.3f);vpt::set_surface(g,n);g.x=bh.point[0];g.y=bh.point[1];g.z=bh.point[2];g.yaw=grand()*6.28f; }
    }
}

fn bool rock_cell(int x,int z) => x>= -vpt::world_size/2&&z>= -vpt::world_size/2&&x<vpt::world_size/2&&z<vpt::world_size/2&&vpt::voxel(x,0,z)!=0;
fn bool open_cell(int x,int z) => x>= -vpt::world_size/2&&z>= -vpt::world_size/2&&x<vpt::world_size/2&&z<vpt::world_size/2&&vpt::voxel(x,0,z)==0&&vpt::voxel(x,-1,z)!=0;


// Floor slabs are 0.64 m deep so blasts can dig real craters (the 1 m terrain under them is not rendered in detailed caves).
const float FLOOR_VOX=0.08f;const int FLOOR_N=50;const int FLOOR_H=10;const float FLOOR_Y= -0.6275f;const int FLOOR_BASE=8;   // 0.64 m of ground under a +0.0125 top: craters up to 0.56 m deep
const float ROCK_VOX=0.125f;const int ROCK_N=32;const int ROCK_H=36;const int CAP_H=4;   // rock 0..4.5 m; caps 4.0..4.5 m over the rest of the rock mass

// Height of the rock mass' top surface (shared by wall blocks and caps, so they join without steps).
fn float rock_top(float wx,float wz,uint seed) => 4.14f+0.24f*vpt::vnoise(wx*0.28f,wz*0.28f,seed+30)+0.06f*vpt::vnoise(wx*0.9f,wz*0.9f,seed+31);   // broad terraces, no fine chatter
// Colour of the up-facing rock top: dusty basalt with broad darker patches, pale ash drifts, sparse grit.
fn uint rock_top_color(float wx,float wz,int x,int y,int z,uint seed)
{
    float broad=vpt::vnoise(wx*0.22f,wz*0.22f,seed+48);float mid=vpt::vnoise(wx*1.1f,wz*1.1f,seed+43);float ash=vpt::vnoise(wx*0.35f+11,wz*0.35f,seed+49);
    float[3] c={50+broad*20+mid*10,46+broad*18+mid*9,42+broad*16+mid*8};
    if(ash>0.64f) { float k=math::min(1.0f,(ash-0.64f)*5)*0.6f;c[0]=vpt::mixf(c[0],92,k);c[1]=vpt::mixf(c[1],88,k);c[2]=vpt::mixf(c[2],82,k); }
    if(vpt::hash3(x,y,z,seed+50)<0.03f) { c[0]*=0.7f;c[1]*=0.7f;c[2]*=0.7f; }   // grit
    float sp=(vpt::hash3(x,y,z,seed+47)-0.5f)*7;return vpt::rgbf(c[0]+sp,c[1]+sp*0.9f,c[2]+sp*0.8f);
}

// Floor slab for the 4 m block at (x0,z0): world-space patterns so neighbouring slabs join seamlessly.
fn void bake_floor(Asset* a,float x0,float z0,uint seed)
{
    for(int z=0;z<FLOOR_N;z++)for(int x=0;x<FLOOR_N;x++)
    {
        float wx=x0+((float)x+0.5f)*FLOOR_VOX;float wz=z0+((float)z+0.5f)*FLOOR_VOX;
        // distance to the nearest rock cell (scree and dust gather at wall feet)
        int cx=(int)math::floor(wx);int cz=(int)math::floor(wz);float wall=9;
        for(int i= -1;i<=1;i++)for(int j= -1;j<=1;j++)if(rock_cell(cx+i,cz+j))
        {
            float dx=math::max(math::max((float)(cx+i)-wx,wx-(float)(cx+i+1)),0.0f);float dz=math::max(math::max((float)(cz+j)-wz,wz-(float)(cz+j+1)),0.0f);
            wall=math::min(wall,math::sqrt(dx*dx+dz*dz));
        }
        float broad=vpt::vnoise(wx*0.3f,wz*0.3f,seed+10);float mid=vpt::vnoise(wx*1.6f,wz*1.6f,seed+11);
        float ash=vpt::vnoise(wx*0.16f+3,wz*0.16f,seed+12);float rust=vpt::vnoise(wx*0.21f,wz*0.21f-7,seed+13);float salt=vpt::vnoise(wx*0.12f-5,wz*0.12f+2,seed+14);
        float[3] c={34+broad*22+mid*8,31+broad*19+mid*7,29+broad*16+mid*6};
        int h=FLOOR_BASE;   // voxel layers: BASE = flat ground (top at +0.0125), +1 = ripple crest / crust, +2 = pebble
        if(ash>0.58f)
        {
            float k=math::min(1.0f,(ash-0.58f)*5);c[0]=vpt::mixf(c[0],96,k*0.7f);c[1]=vpt::mixf(c[1],92,k*0.7f);c[2]=vpt::mixf(c[2],86,k*0.7f);
            float dir=vpt::vnoise(wx*0.05f,wz*0.05f,seed+15)*3.14159f;float ph=(wx*math::cos(dir)+wz*math::sin(dir))*7+vpt::vnoise(wx*0.8f,wz*0.8f,seed+16)*5;
            if(k>0.75f&&math::sin(ph)>0.85f) { h=FLOOR_BASE+1;c[0]+=6;c[1]+=6;c[2]+=5; }   // faint wind ripples in the ash
        }
        if(rust>0.68f) { float k=math::min(1.0f,(rust-0.68f)*6);c[0]=vpt::mixf(c[0],98,k*0.6f);c[1]=vpt::mixf(c[1],58,k*0.6f);c[2]=vpt::mixf(c[2],40,k*0.6f); }
        if(salt>0.76f) { float k=math::min(1.0f,(salt-0.76f)*8);c[0]=vpt::mixf(c[0],150,k*0.8f);c[1]=vpt::mixf(c[1],146,k*0.8f);c[2]=vpt::mixf(c[2],136,k*0.8f);
            }   // salt pans stay flat (raised crust plates read as noise from above)
        // cracks: thin dark lines on a ridged noise
        float cr=math::abs(vpt::vnoise(wx*0.9f,wz*0.9f,seed+18)-0.5f);if(cr<0.018f&&salt<0.76f) { c[0]*=0.45f;c[1]*=0.45f;c[2]*=0.45f;h=FLOOR_BASE; }
        // pebbles on a 0.25 m jittered grid; denser and bigger near walls (scree)
        float px=wx*4;float pz=wz*4;int gx=(int)math::floor(px);int gz=(int)math::floor(pz);
        float dens=0.10f+0.45f*math::max(0.0f,1-wall/1.2f);
        for(int i= -1;i<=1;i++)for(int j= -1;j<=1;j++)
        {
            int qx=gx+i;int qz=gz+j;if(vpt::hash2(qx,qz,seed+19)>dens)continue;
            float ox=(float)qx+vpt::hash2(qx,qz,seed+20);float oz=(float)qz+vpt::hash2(qx,qz,seed+21);float rad=(0.18f+vpt::hash2(qx,qz,seed+22)*0.35f)*(wall<0.8f?1.5f:1);
            float d=math::sqrt((px-ox)*(px-ox)+(pz-oz)*(pz-oz));if(d>rad)continue;
            float tone=vpt::hash2(qx,qz,seed+23);int top=d<rad*0.55f?FLOOR_BASE+2:FLOOR_BASE+1;
            if(top>h) { h=top;c=(float[3]){52+tone*40,47+tone*34,42+tone*30};if(d>rad*0.7f) { c[0]*=0.75f;c[1]*=0.75f;c[2]*=0.75f; } }
        }
        if(wall<0.5f) { float k=1-wall/0.5f;c[0]*=1-0.35f*k;c[1]*=1-0.35f*k;c[2]*=1-0.33f*k; }   // shadowed damp foot of the wall
        for(int y=0;y<h;y++)
        {
            float sp=(vpt::hash3(x,y,z,seed+24)-0.5f)*10;float k=y==h-1?1:y>=FLOOR_BASE-1?0.7f:0.45f;   // deeper layers: darker packed dirt (crater walls)
            a.data[(y*FLOOR_N+z)*FLOOR_N+x]=vpt::rgbf((c[0]+sp)*k,(c[1]+sp*0.9f)*k,(c[2]+sp*0.8f)*k);
        }
    }
}
// Rock for the 4 m block at (x0,z0): the 1 m terrain rock grown by a noisy margin (always >= 0.09 m, so the
// terrain stays fully inside), rounded lip, strata, cracks, mineral veins. Interior voxels get one flat colour.
fn void bake_rock(Asset* a,float x0,float z0,uint seed)
{
    float[ROCK_N*ROCK_N] dist;
    for(int z=0;z<ROCK_N;z++)for(int x=0;x<ROCK_N;x++)
    {
        float wx=x0+((float)x+0.5f)*ROCK_VOX;float wz=z0+((float)z+0.5f)*ROCK_VOX;int cx=(int)math::floor(wx);int cz=(int)math::floor(wz);float best=9;
        for(int i= -1;i<=1;i++)for(int j= -1;j<=1;j++)if(rock_cell(cx+i,cz+j))
        {
            float dx=math::max(math::max((float)(cx+i)-wx,wx-(float)(cx+i+1)),0.0f);float dz=math::max(math::max((float)(cz+j)-wz,wz-(float)(cz+j+1)),0.0f);
            best=math::min(best,math::sqrt(dx*dx+dz*dz));
        }
        dist[z*ROCK_N+x]=best;
    }
    // pass 1: solid
    for(int z=0;z<ROCK_N;z++)for(int x=0;x<ROCK_N;x++)
    {
        float d=dist[z*ROCK_N+x];if(d>0.8f)continue;
        float wx=x0+((float)x+0.5f)*ROCK_VOX;float wz=z0+((float)z+0.5f)*ROCK_VOX;
        float top=rock_top(wx,wz,seed)-d*0.9f;
        for(int y=0;y<ROCK_H;y++)
        {
            float wy=((float)y+0.5f)*ROCK_VOX;if(wy>=top)break;
            bool solid=d<=0;
            if(!solid)
            {
                float off=0.14f+0.24f*vpt::vnoise3(wx*1.1f,wy*1.1f,wz*1.1f,seed+32)+0.10f*vpt::vnoise3(wx*3.5f,wy*3.5f,wz*3.5f,seed+33);
                off+=0.07f*math::sin(wy*6.5f+vpt::vnoise(wx*0.4f,wz*0.4f,seed+34)*6);   // strata ledges
                if(wy<0.7f)off+=0.28f*(1-wy/0.7f)*(1-wy/0.7f)*vpt::vnoise(wx*2,wz*2,seed+35);   // talus at the foot
                if(math::abs(vpt::vnoise3(wx*0.8f,wy*0.6f,wz*0.8f,seed+36)-0.5f)<0.03f)off-=0.12f;   // crevices
                solid=d<math::max(off,0.09f);   // >= 0.09: the first fine voxel ring outside the terrain is always filled
            }
            if(solid)a.data[(y*ROCK_N+z)*ROCK_N+x]=1;
        }
    }
    // pass 2: colour (only voxels that can be seen get the expensive palette)
    for(int y=0;y<ROCK_H;y++)for(int z=0;z<ROCK_N;z++)for(int x=0;x<ROCK_N;x++)
    {
        int at=(y*ROCK_N+z)*ROCK_N+x;if(!a.data[at])continue;
        bool face=x==0||z==0||x==ROCK_N-1||z==ROCK_N-1||y==ROCK_H-1||!a.data[at-1]||!a.data[at+1]||!a.data[at-ROCK_N]||!a.data[at+ROCK_N]||(y+1<ROCK_H&&!a.data[at+ROCK_N*ROCK_N]);
        if(!face) { a.data[at]=vpt::rgba(30,28,26);continue; }
        float wx=x0+((float)x+0.5f)*ROCK_VOX;float wz=z0+((float)z+0.5f)*ROCK_VOX;float wy=((float)y+0.5f)*ROCK_VOX;
        bool up=y+1>=ROCK_H||!a.data[at+ROCK_N*ROCK_N];
        a.data[at]=rock_color(wx,wy,wz,up,seed);
    }
}
fn uint rock_color(float wx,float wy,float wz,bool up,uint seed)
{
    int x=(int)math::floor(wx/ROCK_VOX);int y=(int)math::floor(wy/ROCK_VOX);int z=(int)math::floor(wz/ROCK_VOX);
    {
        if(up&&wy>3.6f)return rock_top_color(wx,wz,x,y,z,seed);
        float band=vpt::vnoise(wx*0.05f+wz*0.03f,wy*1.25f+vpt::vnoise(wx*0.3f,wz*0.3f,seed+40)*1.4f,seed+41);
        float[3] c=band<0.45f?(float[3]){46,42,39}:band<0.7f?(float[3]){60,51,43}:band<0.86f?(float[3]){40,37,35}:(float[3]){94,60,40};
        if(math::abs(band-0.62f)<0.012f)c=(float[3]){112,104,92};   // thin pale tuff seams
        float n=vpt::vnoise3(wx*2.2f,wy*2.2f,wz*2.2f,seed+42);float k=0.8f+0.07f*wy+(n-0.5f)*0.3f;
        if(up) { c=(float[3]){vpt::mixf(c[0],70,0.4f),vpt::mixf(c[1],64,0.4f),vpt::mixf(c[2],58,0.4f)}; }   // ledges catch dust
        if(wy<0.5f&&!up)k*=0.7f+0.6f*wy;   // damp, shadowed base
        if(math::abs(vpt::vnoise3(wx*0.8f,wy*0.6f,wz*0.8f,seed+36)-0.5f)<0.04f)k*=0.45f;   // crevice shadows
        float vein=vpt::vnoise3(wx*1.7f,wy*1.7f,wz*1.7f,seed+44);
        if(vein>0.86f&&vpt::hash3(x,y,z,seed+45)<0.35f) { c=vpt::hash2((int)(wx*3),(int)(wz*3),seed+46)<0.6f?(float[3]){104,84,150}:(float[3]){150,116,66};k=0.9f; }   // violet crystal / ochre flecks
        float sp=(vpt::hash3(x,y,z,seed+47)-0.5f)*9;
        return vpt::rgbf(c[0]*k+sp,c[1]*k+sp*0.9f,c[2]*k+sp*0.8f);
    }
}

// Cap over a 4 m block of the rock mass that no room touches: just the rock top surface (4.0..4.5 m).
// Cap over a 4 m block of the rock mass that no room touches: just the rock top surface (4.0..4.5 m). Voxel size
// comes from the asset (0.125 m near the rooms, 0.25 m far away when the budget is tight).
fn void bake_cap(Asset* a,float x0,float z0,uint seed)
{
    int n=a.dx;int hmax=a.dy;float v=a.size;
    for(int z=0;z<n;z++)for(int x=0;x<n;x++)
    {
        float wx=x0+((float)x+0.5f)*v;float wz=z0+((float)z+0.5f)*v;
        if(!rock_cell((int)math::floor(wx),(int)math::floor(wz)))continue;
        int h=vpt::clampi((int)math::ceil((rock_top(wx,wz,seed)-4)/v),1,hmax);
        for(int y=0;y<h;y++)a.data[(y*n+z)*n+x]=y==h-1?rock_top_color(wx,wz,x,y+32,z,seed):vpt::rgba(30,28,26);
    }
    for(int y=0;y<hmax;y++)for(int z=0;z<n;z++)for(int x=0;x<n;x++)
    {
        int at=(y*n+z)*n+x;if(!a.data[at]||(y+1<hmax&&a.data[at+n*n]==0)||y+1==hmax)continue;
        bool side=(x>0&&!a.data[at-1])||(x+1<n&&!a.data[at+1])||(z>0&&!a.data[at-n])||(z+1<n&&!a.data[at+n]);
        if(side)a.data[at]=vpt::rgba(44,40,37);   // exposed step sides: rock-face tone
    }
}

// Cave roof over everything near the open cave: 0.25 m voxels (0.5 m if the budget is tight), from 4.0 m up.
// Its underside domes up toward the middle of chambers (4.5 m at the walls .. ~5.9 m) and drips stalactites;
// over rock it comes down onto the rock top, so the cave is closed. Shown only in the third-person view.
const float ROOF_Y=4.0f;const int ROOF_N=16;const int ROOF_H=11;
fn float rock_distance(float wx,float wz,int reach)
{
    int cx=(int)math::floor(wx);int cz=(int)math::floor(wz);float best=(float)reach+1;
    for(int i= -reach;i<=reach;i++)for(int j= -reach;j<=reach;j++)if(rock_cell(cx+i,cz+j)||!open_cell(cx+i,cz+j))
    {
        float dx=math::max(math::max((float)(cx+i)-wx,wx-(float)(cx+i+1)),0.0f);float dz=math::max(math::max((float)(cz+j)-wz,wz-(float)(cz+j+1)),0.0f);
        best=math::min(best,math::sqrt(dx*dx+dz*dz));
    }
    return best;
}
// Underside height of the cave roof at (wx,wz). Over rock it comes down onto the rock top (closed cave); over
// open cave it rises into big uneven domes away from the walls, with lumps, hollows and clusters of pointed
// stalactites (cones on a jittered grid), lower and tighter over the narrow tunnels.
fn float roof_under(float wx,float wz,uint seed)
{
    float d=rock_distance(wx,wz,6);if(d<=0)return ROOF_Y;
    float u=4.35f+2.3f*(1-math::exp(-d/2.6f));
    float k=math::min(1.0f,d/1.8f);
    u+=(vpt::vnoise(wx*0.11f,wz*0.11f,seed+90)-0.5f)*1.8f*k;   // big domes and dips
    u+=(vpt::vnoise(wx*0.42f,wz*0.42f,seed+97)-0.5f)*0.8f*k;   // lumps
    u+=(vpt::vnoise(wx*1.3f,wz*1.3f,seed+98)-0.5f)*0.22f;      // rough surface
    // stalactites
    float gx=wx/1.15f;float gz=wz/1.15f;int cx=(int)math::floor(gx);int cz=(int)math::floor(gz);float hang=0;
    for(int i= -1;i<=1;i++)for(int j= -1;j<=1;j++)
    {
        int qx=cx+i;int qz=cz+j;if(vpt::hash2(qx,qz,seed+91)>0.42f)continue;
        float ox=((float)qx+vpt::hash2(qx,qz,seed+99))*1.15f;float oz=((float)qz+vpt::hash2(qx,qz,seed+100))*1.15f;
        float rad=0.22f+vpt::hash2(qx,qz,seed+101)*0.3f;float len=(0.4f+vpt::hash2(qx,qz,seed+102)*1.6f)*math::min(1.0f,d/1.2f);
        float dd=math::sqrt((wx-ox)*(wx-ox)+(wz-oz)*(wz-oz))/rad;if(dd<1)hang=math::max(hang,len*math::pow(1-dd,1.6f));
    }
    u-=hang;
    return math::max(u,3.3f);
}
fn void bake_roof(Asset* a,float x0,float z0,float base,float* under,uint seed)
{
    int n=a.dx;float v=a.size;
    for(int z=0;z<n;z++)for(int x=0;x<n;x++)
    {
        float wx=x0+((float)x+0.5f)*v;float wz=z0+((float)z+0.5f)*v;float u=under[z*n+x];
        for(int y=0;y<a.dy;y++)
        {
            float wy=base+((float)y+0.5f)*v;if(wy<u)continue;
            bool face=wy-v<u;float t=vpt::vnoise3(wx*1.5f,wy*1.5f,wz*1.5f,seed+92);
            float k=face?0.85f+t*0.35f:0.5f;bool tip=face&&wy<4.2f;float wet=face&&(tip||vpt::vnoise(wx*2.2f,wz*2.2f,seed+93)>0.75f)?12:0;
            uint c=vpt::rgbf(37*k+wet,34*k+wet,32*k+wet*1.1f);
            // a few faint bioluminescent growths
            if(face&&vpt::vnoise(wx*2.6f,wz*2.6f,seed+94)>0.9f&&vpt::hash2((int)(wx*4),(int)(wz*4),seed+95)<0.4f)
            { c=((vpt::hash2((int)(wx*0.7f),(int)(wz*0.7f),seed+96)<0.5f?vpt::rgbf(26,80,72):vpt::rgbf(64,38,90))&0xffffffu)|((uint)121<<24); }
            a.data[(y*n+z)*n+x]=c;
        }
    }
}
// Bakes the roof block at (x0,z0) with voxel size v: only the shell from the lowest underside to 2 voxels above
// the highest one is stored (cropped), which is what makes 0.125 m affordable. cost_only: just count voxels.
// mode 0: all 0.125 m; 1: 0.25 m where the piece only covers rock (it just meets the wall tops); 2: all 0.25 m
fn long roof_block(int bx,int bz,float x0,float z0,int mode,uint seed,bool cost_only)
{
    // four 2 m pieces, each cropped to its own height range (a stalactite only makes its own piece tall)
    long total=0;
    for(int q=0;q<4;q++)
    {
        float px=x0+(float)(q&1)*2;float pz=z0+(float)(q>>1)*2;
        bool over_open=false;for(int i=0;i<2;i++)for(int j=0;j<2;j++)if(open_cell((int)px+i,(int)pz+j))over_open=true;
        float v=mode==0||(mode==1&&over_open)?0.125f:0.25f;int n=(int)math::round(2/v);float[16*16] under;float lo=1e9f;float hi= -1e9f;
        for(int z=0;z<n;z++)for(int x=0;x<n;x++) { float u=roof_under(px+((float)x+0.5f)*v,pz+((float)z+0.5f)*v,seed);under[z*n+x]=u;lo=math::min(lo,u);hi=math::max(hi,u); }
        float base=math::floor(lo/v)*v;int dy=(int)math::ceil((hi-base)/v)+2;total+=(long)n*n*dy;
        if(cost_only)continue;
        Asset a={};if(!vpt::allocate_asset(&a,n,dy,n,v))continue;
        bake_roof(&a,px,pz,base,&under,seed);a.roof=true;int id=vpt::add_generated_asset(&a,rl::text_format("cave-roof-%d-%d-%d",bx,bz,q));
        if(id>=0)vpt::instances[vpt::instance_count++]={id,px+1,base,pz+1,0,1,0};
    }
    return total;
}

// Shows / hides the roof (third-person view on, everything else off). Re-applies if something reset hidden[].
bool roof_shown;
fn void set_roof_visible(bool v)
{
    if(gen_active&&gen_layer==0)
    {
        int inside= -1;if(vpt::controlled_rig>=0&&vpt::controlled_rig<vpt::rig_count) { Rig* r=&vpt::rigs[vpt::controlled_rig];inside=surface_inside_cave({r.x,r.y,r.z}); }
        bool changed=false;surface_cutaway_cave= -1;float dt=vpt::clampf(rl::get_frame_time(),0.016f,0.05f);
        for(int i=0;i<vpt::instance_count;i++)if(vpt::assets[vpt::instances[i].asset].roof)
        {
            Asset* a=&vpt::assets[vpt::instances[i].asset];float target=!v&&inside>=0&&a.roof_group==inside+1?0.88f:0;
            float before=vpt::roof_cutaway[i];vpt::roof_cutaway[i]+=vpt::clampf(target-before,-dt*4,dt*4);
            if(vpt::hidden[i]||math::abs(before-vpt::roof_cutaway[i])>0.0001f)changed=true;
            if(!v&&inside>=0&&a.roof_group==inside+1&&vpt::roof_cutaway[i]>0.5f)surface_cutaway_cave=inside;
            vpt::hidden[i]=false;   // outside roofs stay visible; only the occupied cave becomes see-through
        }
        if(changed)vpt::rig_revision++;return;
    }
    int first= -1;for(int i=0;i<vpt::instance_count;i++)if(vpt::assets[vpt::instances[i].asset].roof) { first=i;break; }
    if(first<0||(roof_shown==v&&vpt::hidden[first]==!v))return;
    roof_shown=v;
    for(int i=0;i<vpt::instance_count;i++)
    {
        Asset* a=&vpt::assets[vpt::instances[i].asset];
        if(a.roof) { vpt::hidden[i]=!v; } else if(a.generated&&!a.ground&&a.no_pick&&a.size>=0.1f) { vpt::hidden[i]=v; }   // rock tops are never seen under the roof: cull them
    }
    vpt::rig_revision++;
}

// Covers the carved 1 m terrain with the detail layer. Works on any scene carved like the depths (rock from
// y=0, floor below). Respects the voxel atlas budget: returns false (and adds nothing) if it would not fit.
// Floors and caps are never picked on the CPU (they sit within cm of the terrain the game already collides
// with), so the extra instances cost nothing in gameplay ray casts.
const int BLOCK_NONE=0;const int BLOCK_FLOOR=1;const int BLOCK_ROCK=2;const int BLOCK_CAP=4;
fn int block_kind(int x0,int z0)
{
    bool open=false;bool rock=false;bool near=false;
    for(int x=x0-1;x<=x0+4;x++)for(int z=z0-1;z<=z0+4;z++)
    {
        bool inside_block=x>=x0&&x<x0+4&&z>=z0&&z<z0+4;
        if(open_cell(x,z)) { near=true;if(inside_block)open=true; }
        if(inside_block&&rock_cell(x,z))rock=true;
    }
    return (open?BLOCK_FLOOR:0)|(rock&&near?BLOCK_ROCK:0)|(rock&&!near?BLOCK_CAP:0);
}
fn bool bake_cave_detail(uint seed)
{
    int half=vpt::world_size/2;int blocks=vpt::world_size/4;
    int count=0;
    for(int bz=0;bz<blocks;bz++)for(int bx=0;bx<blocks;bx++)
    {
        int k=block_kind(bx*4-half,bz*4-half);
        if(k&BLOCK_FLOOR)count++;if(k&BLOCK_ROCK)count+=4;if(k&BLOCK_CAP)count++;if(k&(BLOCK_FLOOR|BLOCK_ROCK))count+=8;   // + roof pieces (the roof also spans one block past the walls)
    }
    if(vpt::instance_count+count>vpt::MAX_INSTANCES-64||vpt::asset_count+count>vpt::MAX_ASSETS-64)
    { vpt::report("Detailed cave skipped: too many objects for this layout.");return false; }
    // 1) floors and walls: always at full detail (this is what the robot walks and fights in)
    bool[32*32] near;   // blocks within one block of a floor/wall block: their caps are seen next to the rooms
    for(int bz=0;bz<blocks;bz++)for(int bx=0;bx<blocks;bx++)
    {
        int x0=bx*4-half;int z0=bz*4-half;int k=block_kind(x0,z0);float cx=(float)x0+2;float cz=(float)z0+2;
        if(k&(BLOCK_FLOOR|BLOCK_ROCK))for(int i= -1;i<=1;i++)for(int j= -1;j<=1;j++)if(bx+i>=0&&bz+j>=0&&bx+i<blocks&&bz+j<blocks&&bx+i<32&&bz+j<32)near[(bz+j)*32+bx+i]=true;
        if(k&BLOCK_FLOOR)
        {
            Asset a={};if(vpt::allocate_asset(&a,FLOOR_N,FLOOR_H,FLOOR_N,FLOOR_VOX))
            {
                bake_floor(&a,(float)x0,(float)z0,seed);a.no_pick=true;int id=vpt::add_generated_asset(&a,rl::text_format("cave-floor-%d-%d",bx,bz));
                if(id>=0)vpt::instances[vpt::instance_count++]={id,cx,FLOOR_Y,cz,0,1,0};
            }
        }
        if(k&BLOCK_ROCK)
        {
            // Baked as one 4 m block, then split into 2 m quarters cropped to their rock: rays crossing the open
            // room in front of a wall no longer march through a box of empty voxels (that was the GPU cost).
            Asset a={};if(vpt::allocate_asset(&a,ROCK_N,ROCK_H,ROCK_N,ROCK_VOX))
            {
                bake_rock(&a,(float)x0,(float)z0,seed);
                for(int q=0;q<4;q++)
                {
                    int qx=(q&1)*ROCK_N/2;int qz=(q>>1)*ROCK_N/2;int[3] lo={999,999,999};int[3] hi={-1,-1,-1};
                    for(int y=0;y<ROCK_H;y++)for(int z=qz;z<qz+ROCK_N/2;z++)for(int x=qx;x<qx+ROCK_N/2;x++)if(a.data[(y*ROCK_N+z)*ROCK_N+x])
                    { lo[0]=math::min(lo[0],x);lo[1]=math::min(lo[1],y);lo[2]=math::min(lo[2],z);hi[0]=math::max(hi[0],x);hi[1]=math::max(hi[1],y);hi[2]=math::max(hi[2],z); }
                    if(hi[0]<0)continue;
                    int dx=hi[0]-lo[0]+1;int dy=hi[1]-lo[1]+1;int dz=hi[2]-lo[2]+1;
                    Asset part={};if(!vpt::allocate_asset(&part,dx,dy,dz,ROCK_VOX))continue;
                    for(int y=0;y<dy;y++)for(int z=0;z<dz;z++)for(int x=0;x<dx;x++)part.data[(y*dz+z)*dx+x]=a.data[((y+lo[1])*ROCK_N+z+lo[2])*ROCK_N+x+lo[0]];
                    int id=vpt::add_generated_asset(&part,rl::text_format("cave-rock-%d-%d-%d",bx,bz,q));
                    if(id>=0)vpt::instances[vpt::instance_count++]={id,(float)x0+((float)lo[0]+(float)dx*0.5f)*ROCK_VOX,(float)lo[1]*ROCK_VOX,(float)z0+((float)lo[2]+(float)dz*0.5f)*ROCK_VOX,0,1,0};
                }
                vpt::free_asset(&a);
            }
        }
    }
    // 2) what is left, in priority order: carvable prop copies, then the roof, then the rock tops.
    //    Everything degrades instead of disappearing: --detailed never falls back to flat.
    long fine=ROCK_N*CAP_H*ROCK_N;long coarse=(ROCK_N/2)*2*(ROCK_N/2);long n_near=0;long n_far=0;long n_roof=0;
    for(int bz=0;bz<blocks;bz++)for(int bx=0;bx<blocks;bx++)
    {
        if(block_kind(bx*4-half,bz*4-half)&BLOCK_CAP) { if(bx<32&&bz<32&&near[bz*32+bx]) { n_near++; } else { n_far++; } }
        if(bx<32&&bz<32&&near[bz*32+bx])n_roof++;
    }
    long[3] roof_cost;
    for(int bz=0;bz<blocks;bz++)for(int bx=0;bx<blocks;bx++)if(bx<32&&bz<32&&near[bz*32+bx]) { for(int m=0;m<3;m++)roof_cost[m]+=roof_block(bx,bz,(float)(bx*4-half),(float)(bz*4-half),m,seed,true); }
    long left=(long)GEN_ATLAS_BUDGET-700000-(long)vpt::active_asset_pixels();
    long props_min=250000;   // keep a little room for carvable prop copies
    long caps_min=(n_near+n_far)*coarse;
    int roof_mode=roof_cost[0]+caps_min+props_min<=left?0:roof_cost[1]+caps_min+props_min<=left?1:2;
    bool roof_hi=roof_mode==0;
    for(int bz=0;bz<blocks;bz++)for(int bx=0;bx<blocks;bx++)if(bx<32&&bz<32&&near[bz*32+bx]) { (void)roof_block(bx,bz,(float)(bx*4-half),(float)(bz*4-half),roof_mode,seed,false); }
    left=(long)GEN_ATLAS_BUDGET-700000-(long)vpt::active_asset_pixels()-props_min;
    int quality=(n_near+n_far)*fine<=left?0:n_near*fine+n_far*coarse<=left?1:2;
    for(int bz=0;bz<blocks;bz++)for(int bx=0;bx<blocks;bx++)
    {
        int x0=bx*4-half;int z0=bz*4-half;if(!(block_kind(x0,z0)&BLOCK_CAP))continue;
        bool is_near=bx<32&&bz<32&&near[bz*32+bx];bool coarse_cap=quality==2||(quality==1&&!is_near);
        Asset a={};int nn=coarse_cap?ROCK_N/2:ROCK_N;
        if(vpt::allocate_asset(&a,nn,coarse_cap?2:CAP_H,nn,coarse_cap?ROCK_VOX*2:ROCK_VOX))
        {
            bake_cap(&a,(float)x0,(float)z0,seed);a.no_pick=true;int id=vpt::add_generated_asset(&a,rl::text_format("cave-cap-%d-%d",bx,bz));
            if(id>=0)vpt::instances[vpt::instance_count++]={id,(float)x0+2,4,(float)z0+2,0,1,0};
        }
    }
    gen_cap_quality=quality;gen_roof_fine=roof_hi;gen_roof_mode=roof_mode;
    vpt::make_props_unique((long)vpt::MAX_ATLAS_PIXELS-700000-(long)vpt::active_asset_pixels());   // carvable copies with whatever is left
    vpt::terrain_hidden=true;vpt::touch_instances();return true;
}

// "gen:SEED", "gen:SEED:detailed", "gen:random[:detailed]": a generated layer instead of a scene file.
fn bool is_gen_spec(ZString spec) => spec.str_view().starts_with("gen:")||spec.str_view().starts_with("surface:");
fn bool open_gen_spec(ZString spec)
{
    String text=spec.str_view();bool surface=text.starts_with("surface:");uint seed=0;bool detailed=surface;bool random=true;int i=surface?8:4;
    while(i<(int)text.len&&text[i]>='0'&&text[i]<='9') { seed=seed*10+(uint)(text[i]-'0');i++;random=false; }
    foreach(k,ch:text)if(ch=='d'&&k+8<=text.len&&text[k:8]=="detailed")detailed=true;
    if(random)seed=(uint)rl::get_random_value(1,2147483646);
    return generate_layer(seed,surface?0:-1,detailed);
}

// ---------------------------------------------------------------- destruction (detailed caves)
// Blasts and hits carve the generated detail: floors get craters (scorched bowl + rubble rim, up to 0.29 m deep),
// walls get gouged. "Up to a point that makes sense": rock deeper than WALL_DEPTH from the original open space is
// bedrock, so walls never open up between rooms; the 1 m collision terrain is never changed (it is not rendered).
const float WALL_DEPTH=0.9f;
fn bool destructible_cave() => vpt::terrain_hidden&&gen_active;
fn float open_distance(float wx,float wz)
{
    int cx=(int)math::floor(wx);int cz=(int)math::floor(wz);float best=9;
    for(int i= -2;i<=2;i++)for(int j= -2;j<=2;j++)if(open_cell(cx+i,cz+j))
    {
        float dx=math::max(math::max((float)(cx+i)-wx,wx-(float)(cx+i+1)),0.0f);float dz=math::max(math::max((float)(cz+j)-wz,wz-(float)(cz+j+1)),0.0f);
        best=math::min(best,math::sqrt(dx*dx+dz*dz));
    }
    return best;
}
fn bool is_rock_part(Asset* a) => a.generated&&!a.no_pick&&!a.roof;
fn bool is_floor_slab(Asset* a) => a.generated&&a.no_pick&&a.size<0.1f;
// radius: crater/gouge size in metres (bullet ~0.15, rocket ~0.6-0.9, bloater ~1.4); scorch: 0..1 soot.
// props_only: carve placed props but leave floors/rock (rockets bite props over their whole blast radius).
fn void blast_terrain(rl::RLVector3 p,float radius,float scorch,bool props_only=false)
{
    if(!gen_active||radius<=0)return;
    for(int id=0;id<vpt::instance_count;id++)
    {
        Asset* a=&vpt::assets[vpt::instances[id].asset];if(vpt::hidden[id]||!(a.prop_clone||(!props_only&&a.generated&&vpt::terrain_hidden)))continue;
        rl::RLVector3 lo;rl::RLVector3 hi;vpt::cached_bounds(id,&lo,&hi);float r=radius*1.3f;
        if(p[0]+r<lo[0]||p[0]-r>hi[0]||p[1]+r<lo[1]||p[1]-r>hi[1]||p[2]+r<lo[2]||p[2]-r>hi[2])continue;
        Instance it=vpt::instances[id];rl::RLVector3 base={it.x,it.y,it.z}+a.origin;bool changed=false;
        if(gen_layer==0&&a.generated&&a.ground&&!a.roof) { changed=crater_surface(a,base,p,radius,scorch); }
        else if(is_floor_slab(a)) { changed=crater_floor(a,base,p,radius,scorch); }
        else if(is_rock_part(a)) { changed=gouge_rock(a,base,p,radius,scorch); }
        else if(a.prop_clone) { changed=vpt::carve_prop(id,a,p,radius,scorch);if(changed)vpt::note_carved_prop(id,p); }
        if(changed) { vpt::refresh_asset_voxels(vpt::instances[id].asset);blast_hits++; }
    }
}
int blast_hits;   // assets changed by blast_terrain (tests)
// Layer 0 ground (flats, hills, den floors): the fine terrain is a thin shell over nothing, so a plain gouge
// would punch see-through holes. Carve a jagged sphere, then LINE the hole: every column that had ground gets
// a two-voxel skin just outside the blast, below its original top (charred toward the centre). The asset's
// lowest layer is never removed.
fn bool crater_surface(Asset* a,rl::RLVector3 base,rl::RLVector3 p,float radius,float scorch)
{
    float s=a.size;float r=radius*1.15f;float skin=s*2.2f;float reach=r+skin;bool changed=false;
    int x0=vpt::clampi((int)((p[0]-reach-base[0])/s),0,a.dx-1);int x1=vpt::clampi((int)((p[0]+reach-base[0])/s),0,a.dx-1);
    int y0=vpt::clampi((int)((p[1]-reach-base[1])/s),0,a.dy-1);int y1=vpt::clampi((int)((p[1]+reach-base[1])/s),0,a.dy-1);
    int z0=vpt::clampi((int)((p[2]-reach-base[2])/s),0,a.dz-1);int z1=vpt::clampi((int)((p[2]+reach-base[2])/s),0,a.dz-1);
    for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)
    {
        int top= -1;for(int y=a.dy-1;y>=0;y--)if(a.data[(y*a.dz+z)*a.dx+x]) { top=y;break; }
        if(top<0)continue;   // no ground here (sky / cave mouth / den interior): never invent any
        uint tc=a.data[(top*a.dz+z)*a.dx+x];rl::RLColor col=vpt::color(tc);
        float wx=base[0]+((float)x+0.5f)*s;float wz=base[2]+((float)z+0.5f)*s;
        for(int y=math::max(y0,0);y<=math::min(y1,top);y++)
        {
            int at=(y*a.dz+z)*a.dx+x;float wy=base[1]+((float)y+0.5f)*s;
            float jag=0.8f+0.4f*vpt::vnoise3(wx*2.6f,wy*2.6f,wz*2.6f,gen_seed+66);
            float d=math::sqrt((wx-p[0])*(wx-p[0])+(wy-p[1])*(wy-p[1])+(wz-p[2])*(wz-p[2]));float rr=r*jag;
            if(d<rr&&y>0) { if(a.data[at]) { a.data[at]=0;changed=true; } continue; }
            if(d<rr+skin)
            {
                // crater wall: fill (lines the hollow shell) and char it; darker deeper and nearer the centre
                float k=0.55f+0.35f*math::min(1.0f,(d-rr)/skin)-math::min(0.25f,(float)(top-y)*s*0.4f);
                float soot=math::min(1.0f,scorch*(1-d/(rr+skin))*1.6f);
                a.data[at]=vpt::rgbf(vpt::mixf((float)col[0]*k,16,soot),vpt::mixf((float)col[1]*k,14,soot),vpt::mixf((float)col[2]*k,13,soot));changed=true;
            }
        }
    }
    return changed;
}
fn bool crater_floor(Asset* a,rl::RLVector3 base,rl::RLVector3 p,float radius,float scorch)
{
    if(p[1]>radius+0.4f)return false;   // blast high above the floor: no crater
    float s=a.size;bool changed=false;float depth_max=math::min(radius*0.48f,(float)(FLOOR_BASE-1)*s);   // bloater ~0.56 m, rocket ~0.3 m, bullet a few cm
    int x0=vpt::clampi((int)((p[0]-radius*1.3f-base[0])/s),0,a.dx-1);int x1=vpt::clampi((int)((p[0]+radius*1.3f-base[0])/s),0,a.dx-1);
    int z0=vpt::clampi((int)((p[2]-radius*1.3f-base[2])/s),0,a.dz-1);int z1=vpt::clampi((int)((p[2]+radius*1.3f-base[2])/s),0,a.dz-1);
    for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)
    {
        float wx=base[0]+((float)x+0.5f)*s;float wz=base[2]+((float)z+0.5f)*s;
        float jag=0.85f+0.3f*vpt::vnoise(wx*1.6f,wz*1.6f,gen_seed+60);float d=math::sqrt((wx-p[0])*(wx-p[0])+(wz-p[2])*(wz-p[2]))/(radius*jag);
        int top=0;while(top<a.dy&&a.data[(top*a.dz+z)*a.dx+x])top++;
        if(d<1)
        {
            // bowl: dig down, char the new bottom (darker toward the centre)
            int want=math::max(1,FLOOR_BASE-(int)math::round(depth_max*(1-d*d)/s));
            if(want<top) { for(int y=want;y<top;y++)a.data[(y*a.dz+z)*a.dx+x]=0;changed=true;top=want; }
            float k=(0.35f+0.65f*d)*(1-scorch*0.5f*(1-d));uint c=a.data[((top-1)*a.dz+z)*a.dx+x];rl::RLColor cc=vpt::color(c);
            float soot=math::min(1.0f,scorch*(1-d)*1.4f);
            a.data[((top-1)*a.dz+z)*a.dx+x]=vpt::rgbf(vpt::mixf((float)cc[0]*k,16,soot),vpt::mixf((float)cc[1]*k,14,soot),vpt::mixf((float)cc[2]*k,13,soot));changed=true;
        }
        else if(d<1.3f&&radius>=0.35f)
        {
            // ejecta rim: raised rubble lumps
            float rim=1-math::abs(d-1.1f)/0.16f;
            if(rim>0)
            {
                // a continuous lip of thrown-out dirt, a little higher where it peaks; same tone as the ground, sooty
                int want=math::min(a.dy,math::max(top,FLOOR_BASE+1+(rim>0.6f&&radius>0.8f?1:0)));
                uint g=a.data[((top-1)*a.dz+z)*a.dx+x];rl::RLColor gc=vpt::color(g);float k=0.8f+0.15f*vpt::hash2(x,z,gen_seed+63);float soot=scorch*0.35f;
                for(int y=top;y<want;y++) { a.data[(y*a.dz+z)*a.dx+x]=vpt::rgbf(vpt::mixf((float)gc[0]*k,20,soot),vpt::mixf((float)gc[1]*k,18,soot),vpt::mixf((float)gc[2]*k,16,soot));changed=true; }
            }
        }
    }
    return changed;
}
fn bool gouge_rock(Asset* a,rl::RLVector3 base,rl::RLVector3 p,float radius,float scorch)
{
    float s=a.size;bool changed=false;float r=radius*1.2f;   // walls take more of a blast than the floor shows
    int x0=vpt::clampi((int)((p[0]-r-base[0])/s),0,a.dx-1);int x1=vpt::clampi((int)((p[0]+r-base[0])/s),0,a.dx-1);
    int y0=vpt::clampi((int)((p[1]-r-base[1])/s),0,a.dy-1);int y1=vpt::clampi((int)((p[1]+r-base[1])/s),0,a.dy-1);
    int z0=vpt::clampi((int)((p[2]-r-base[2])/s),0,a.dz-1);int z1=vpt::clampi((int)((p[2]+r-base[2])/s),0,a.dz-1);
    for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)
    {
        float wx=base[0]+((float)x+0.5f)*s;float wz=base[2]+((float)z+0.5f)*s;
        if(open_distance(wx,wz)>WALL_DEPTH)continue;   // bedrock
        for(int y=y0;y<=y1;y++)
        {
            int at=(y*a.dz+z)*a.dx+x;if(!a.data[at])continue;
            float wy=base[1]+((float)y+0.5f)*s;float jag=0.75f+0.45f*vpt::vnoise3(wx*2.2f,wy*2.2f,wz*2.2f,gen_seed+64);
            float d=math::sqrt((wx-p[0])*(wx-p[0])+(wy-p[1])*(wy-p[1])+(wz-p[2])*(wz-p[2]));
            if(d<r*jag) { a.data[at]=0;changed=true; }
        }
    }
    if(!changed)return false;
    // re-skin what the blast exposed (interior voxels were a flat fill), with soot near the centre
    int rx0=math::max(x0-1,0);int rx1=math::min(x1+1,a.dx-1);int ry0=math::max(y0-1,0);int ry1=math::min(y1+1,a.dy-1);int rz0=math::max(z0-1,0);int rz1=math::min(z1+1,a.dz-1);
    for(int y=ry0;y<=ry1;y++)for(int z=rz0;z<=rz1;z++)for(int x=rx0;x<=rx1;x++)
    {
        int at=(y*a.dz+z)*a.dx+x;if(!a.data[at])continue;
        bool face=x==0||z==0||y==0||x==a.dx-1||z==a.dz-1||y==a.dy-1||!a.data[at-1]||!a.data[at+1]||!a.data[at-a.dx]||!a.data[at+a.dx]||!a.data[at-a.dx*a.dz]||!a.data[at+a.dx*a.dz];
        if(!face)continue;
        float wx=base[0]+((float)x+0.5f)*s;float wy=base[1]+((float)y+0.5f)*s;float wz=base[2]+((float)z+0.5f)*s;
        float d=math::sqrt((wx-p[0])*(wx-p[0])+(wy-p[1])*(wy-p[1])+(wz-p[2])*(wz-p[2]))/(r*1.3f);if(d>1)continue;
        bool up=y+1>=a.dy||!a.data[at+a.dx*a.dz];rl::RLColor c=vpt::color(rock_color(wx,wy,wz,up,gen_seed));
        float soot=math::min(1.0f,scorch*(1-d)*1.3f);
        a.data[at]=vpt::rgbf(vpt::mixf((float)c[0],14,soot),vpt::mixf((float)c[1],12,soot),vpt::mixf((float)c[2],11,soot));
    }
    return true;
}
