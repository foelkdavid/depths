module depths;
import std::math;
import raylib6::rl;
import vpt;

// Three genuine roofed side caves, cut into surface hills. One salvage den, one wildlife den,
// one alien incursion/boss cave; the seed changes which entrance leads to the boss.
struct SurfaceCave { Vec center;float radius;Vec direction;int content; }
SurfaceCave[3] surface_caves;uint surface_cave_seed=0xffffffff;
// Generator version 1 put every den straight outward (mouth facing the map centre), so with the fixed
// top-down play camera most mouths hid behind their own hill. Version 2 turns the mouth toward the
// camera wherever the hill stays clear of the trail, other dens and the boundary.
const int SURFACE_GEN_VERSION=2;
int surface_cave_version=SURFACE_GEN_VERSION;int surface_cave_built_version= -1;
const float PLAY_CAMERA_ORBIT=0.68f;   // matches main::orbit during play (camera never orbits in game)
fn bool surface_cave_spot_ok(SurfaceCave cave,int index,uint seed)
{
    Vec center=cave.center;float radius=cave.radius;
    if(math::sqrt(center[0]*center[0]+center[2]*center[2])+radius>43)return false;
    for(int s=0;s<SURFACE_STOPS;s++)if(s!=2+index*2)
    { Vec p=surface_stop(s,seed);float dx=p[0]-center[0];float dz=p[2]-center[2];if(dx*dx+dz*dz<(radius+10)*(radius+10))return false; }
    for(int k=0;k<index;k++)
    { Vec o=surface_caves[k].center;float dx=o[0]-center[0];float dz=o[2]-center[2];if(dx*dx+dz*dz<26*26)return false; }
    // The hill must stay off the whole walkable trail (with its width), except inside this den's own entrance cut.
    SurfaceCave keep=surface_caves[index];surface_caves[index]=cave;bool ok=true;
    for(int s=0;s<SURFACE_STOPS-1&&ok;s++)
    {
        Vec a=surface_stop(s,seed);Vec b=surface_stop(s+1,seed);Vec ab=b-a;float len=math::sqrt(vpt::dot(ab,ab));Vec side={-ab[2]/len,0,ab[0]/len};
        for(int k=0;k<=(int)(len*2)&&ok;k++)for(int w= -1;w<=1&&ok;w++)
        {
            Vec p=a+ab*((float)k/(len*2))+side*((float)w*0.9f);
            if(surface_cave_open(index,p[0],p[2])>0)continue;
            float dx=p[0]-center[0];float dz=p[2]-center[2];float d=math::sqrt(dx*dx+dz*dz*1.08f);
            if(6.35f*(1-vpt::smooth(radius+0.8f,radius+4,d))>0.35f)ok=false;
        }
    }
    surface_caves[index]=keep;return ok;
}
fn void init_surface_caves(uint seed)
{
    if(surface_cave_seed==seed&&surface_cave_built_version==surface_cave_version)return;
    surface_cave_seed=seed;surface_cave_built_version=surface_cave_version;int other=0;int boss=(int)(seed%3);
    for(int i=0;i<3;i++)
    {
        Vec stop=surface_stop(2+i*2,seed);Vec direction=vpt::normalized(stop);
        int content=i==boss?2:(other++%2);float radius=content==2?6.2f:4.8f;
        if(surface_cave_version>=2)
        {
            // Try the camera-facing mouth first, then ever wider swings either way (24 headings);
            // nothing valid keeps the old outward den.
            float facing=math::atan2(-math::cos(PLAY_CAMERA_ORBIT),-math::sin(PLAY_CAMERA_ORBIT));
            for(int step=0;step<24;step++)
            {
                float a=facing+(float)((step+1)/2)*(step%2==0?1.0f:-1.0f)*0.2618f;Vec d={math::cos(a),0,math::sin(a)};
                if(surface_cave_spot_ok({stop+d*10,radius,d,content},i,seed)) { direction=d;break; }
            }
        }
        surface_caves[i]={stop+direction*10,radius,direction,content};
    }
}
fn float surface_cave_open(int i,float x,float z)
{
    SurfaceCave c=surface_caves[i];float dx=x-c.center[0];float dz=z-c.center[2];
    float angle=math::atan2(dz,dx);float rough=0.15f*math::sin(angle*5+(float)i);
    float chamber=c.radius+rough-math::sqrt(dx*dx+dz*dz*1.12f);
    // A short, broad entrance from the trail-side stop, not a hole in a sealed hill.
    float along= -(dx*c.direction[0]+dz*c.direction[2]);float across= -dx*c.direction[2]+dz*c.direction[0];
    float end=math::max(3-along,math::max(along-11,0.0f));float distance=math::sqrt(end*end+across*across);
    return math::max(chamber,1.65f-distance);
}
fn int surface_cave_at(float x,float z)
{
    if(!gen_active||gen_layer!=0)return -1;
    init_surface_caves(gen_seed);
    for(int i=0;i<3;i++)if(surface_cave_open(i,x,z)>0)return i;
    return -1;
}
fn float surface_cave_ceiling(int i,float x,float z)
{
    SurfaceCave c=surface_caves[i];float dx=x-c.center[0];float dz=z-c.center[2];float d=math::sqrt(dx*dx+dz*dz);
    return 3.15f+1.1f*(1-vpt::smooth(1,c.radius+0.5f,d))+(vpt::vnoise(x*0.8f,z*0.8f,surface_cave_seed+712)-0.5f)*0.25f;
}
fn float surface_mound(float x,float z)
{
    float mound=0;
    for(int i=0;i<3;i++)
    {
        SurfaceCave c=surface_caves[i];float dx=x-c.center[0];float dz=z-c.center[2];float d=math::sqrt(dx*dx+dz*dz*1.08f);
        float height=(6.1f+(vpt::vnoise(x*0.6f,z*0.6f,surface_cave_seed+713)-0.5f)*0.5f)*(1-vpt::smooth(c.radius+0.8f,c.radius+4,d));
        mound=math::max(mound,height);
    }
    return mound;
}
fn float surface_walk_height(float x,float z)
{
    return surface_cave_at(x,z)>=0?0.12f:surface_height(x,z,gen_seed);
}
fn int surface_inside_cave(Vec p)
{
    int i=surface_cave_at(p[0],p[2]);if(i<0)return -1;
    float ceiling=surface_cave_ceiling(i,p[0],p[2]);
    return p[1]<ceiling-0.35f&&surface_height(p[0],p[2],gen_seed)>ceiling+0.3f?i:-1;
}
fn int surface_roof_group(float x,float z)
{
    for(int i=0;i<3;i++)if(surface_cave_open(i,x,z)> -1.2f&&surface_height(x,z,gen_seed)>surface_cave_ceiling(i,x,z)+0.25f)return i+1;
    return 0;
}
// Split ONLY the roof directly over the hollow from a terrain block. Fading an entire 4 m hillside
// block would expose empty space around the cave (and show the sky through the ground).
fn void split_surface_roof(Asset* a,float x0,float z0,float base,int group)
{
    int x0v=a.dx;int y0v=a.dy;int z0v=a.dz;int x1v= -1;int y1v= -1;int z1v= -1;float v=a.size;
    for(int z=0;z<a.dz;z++)for(int x=0;x<a.dx;x++)
    {
        float wx=x0+((float)x+0.5f)*v;float wz=z0+((float)z+0.5f)*v;
        if(surface_cave_open(group-1,wx,wz)<=0||surface_height(wx,wz,gen_seed)<=surface_cave_ceiling(group-1,wx,wz)+0.25f)continue;
        for(int y=0;y<a.dy;y++)if(a.data[(y*a.dz+z)*a.dx+x])
        { x0v=math::min(x0v,x);x1v=math::max(x1v,x);y0v=math::min(y0v,y);y1v=math::max(y1v,y);z0v=math::min(z0v,z);z1v=math::max(z1v,z); }
    }
    if(x1v<0)return;
    int dx=x1v-x0v+1;int dy=y1v-y0v+1;int dz=z1v-z0v+1;Asset cap={};if(!vpt::allocate_asset(&cap,dx,dy,dz,v))return;
    cap.roof=true;cap.roof_group=group;cap.ground=true;
    for(int z=z0v;z<=z1v;z++)for(int x=x0v;x<=x1v;x++)
    {
        float wx=x0+((float)x+0.5f)*v;float wz=z0+((float)z+0.5f)*v;
        if(surface_cave_open(group-1,wx,wz)<=0||surface_height(wx,wz,gen_seed)<=surface_cave_ceiling(group-1,wx,wz)+0.25f)continue;
        for(int y=y0v;y<=y1v;y++) { int at=(y*a.dz+z)*a.dx+x;cap.data[((y-y0v)*dz+z-z0v)*dx+x-x0v]=a.data[at];a.data[at]=0; }
    }
    int id=vpt::add_generated_asset(&cap,rl::text_format("surface-lid-%d-%d",group,vpt::instance_count));
    if(id>=0)vpt::instances[vpt::instance_count++]={id,x0+((float)x0v+(float)dx*0.5f)*v,base+(float)y0v*v,z0+((float)z0v+(float)dz*0.5f)*v,0,1,0};
}
fn void bake_surface_caves(uint seed)
{
    // Small 2 m pieces cropped per material layer: walls are not hidden with the ceilings.
    for(int i=0;i<3;i++)
    {
        SurfaceCave c=surface_caves[i];int bx0=(int)math::floor((c.center[0]-10)/2);int bz0=(int)math::floor((c.center[2]-9)/2);
        for(int bz=bz0;bz<bz0+10;bz++)for(int bx=bx0;bx<bx0+11;bx++)
        {
            float x0=(float)(bx*2);float z0=(float)(bz*2);float v=0.125f;int n=16;
            bool floor=false;bool wall=false;bool roof=false;
            for(int z=0;z<n;z++)for(int x=0;x<n;x++)
            {
                float wx=x0+((float)x+0.5f)*v;float wz=z0+((float)z+0.5f)*v;float d=surface_cave_open(i,wx,wz);float h=surface_height(wx,wz,seed);
                if(d>=0&&h>0.45f)floor=true;
                if(d>= -0.4f&&d<0&&h>0.6f)wall=true;
                if(d>= -0.3f&&h>surface_cave_ceiling(i,wx,wz)+0.3f)roof=true;
            }
            for(int layer=0;layer<3;layer++)
            {
                if((layer==0&&!floor)||(layer==1&&!wall)||(layer==2&&!roof))continue;
                float base=layer==0?-0.375f:layer==1?0.125f:2.875f;int dy=layer==0?4:layer==1?35:14;
                Asset a={};if(!vpt::allocate_asset(&a,n,dy,n,v))continue;
                a.ground=layer==0;a.no_pick=layer==0;a.roof=layer==2;a.roof_group=layer==2?i+1:0;
                for(int z=0;z<n;z++)for(int x=0;x<n;x++)
                {
                    float wx=x0+((float)x+0.5f)*v;float wz=z0+((float)z+0.5f)*v;float d=surface_cave_open(i,wx,wz);float h=surface_height(wx,wz,seed);float ceiling=surface_cave_ceiling(i,wx,wz);
                    for(int y=0;y<dy;y++)
                    {
                        float wy=base+((float)y+0.5f)*v;bool solid=layer==0?(d>=0&&h>0.45f):layer==1?(d>= -0.4f&&d<0&&wy<=math::min(h,ceiling)):d>= -0.3f&&h>ceiling+0.3f&&wy>=ceiling&&wy<=ceiling+0.3f;
                        if(!solid)continue;float band=0.5f+0.5f*math::sin(wy*7+vpt::vnoise(wx*0.3f,wz*0.3f,seed+714)*2);
                        a.data[(y*n+z)*n+x]=vpt::rgba((int)(48+band*25),(int)(44+band*22),(int)(41+band*18));
                    }
                }
                int id=vpt::add_generated_asset(&a,rl::text_format("surface-den-%d-%d-%d-%d",i,bx,bz,layer));
                if(id>=0)vpt::instances[vpt::instance_count++]={id,x0+1,base,z0+1,0,1,0};
            }
        }
    }
}
