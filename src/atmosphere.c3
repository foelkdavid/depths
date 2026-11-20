module depths;
import std::math;
import raylib6::rl;
import vpt;

// Layer-0 atmosphere, cheap by construction: a fixed pool of tiny dyn cubes (no lights, no picking, no atlas
// changes). Ash motes drift on the wind around the robot (they grow in / shrink out instead of popping), and
// faint glowing spores hang and bob around each side-cave mouth, drawn only when the robot is near.
const int MOTES=30;const int SPORES_PER_CAVE=9;
struct Mote { Vec p;float age;float life;float size;vpt::Quat q;Vec spin;Vec prev; }
Mote[MOTES] motes;bool atmosphere_off;int mote_asset= -1;int spore_asset= -1;bool motes_seeded;

fn void atmosphere_init()
{
    mote_asset=vpt::make_cube_asset("ash-mote",1,0xffffff,0);
    spore_asset=vpt::make_cube_asset("cave-spore",1,vpt::rgba(120,255,214),0.7f);
    if(mote_asset>=0)vpt::pinned_assets[mote_asset]=true;if(spore_asset>=0)vpt::pinned_assets[spore_asset]=true;
    motes_seeded=false;
}
fn Vec wind_now() { float gust=0.65f+0.45f*math::sin(game_time*0.53f)+0.25f*math::sin(game_time*1.37f+1.1f);return (Vec){1.15f,0,0.42f}*gust; }
fn void respawn_mote(Mote* m,Vec around,bool anywhere)
{
    float a=gr()*6.2832f;float r=anywhere?math::sqrt(gr())*10:8+gr()*2.5f;Vec w=nrm(wind_now()+(Vec){0.0001f,0,0});
    Vec off={math::cos(a)*r,0,math::sin(a)*r};if(!anywhere&&vpt::dot(off,w)>0)off=off-w*(2*vpt::dot(off,w));   // re-enter upwind
    m.p=around+off+(Vec){0,0.25f+gr()*3.2f,0};m.prev=m.p;m.age=0;m.life=4+gr()*6;m.size=0.018f+gr()*0.02f;
    m.q=vpt::qaxis(rand_dir(),gr()*6.28f);m.spin=rand_dir()*(1+gr()*4);
}
fn void atmosphere_draw(float dt)
{
    if(atmosphere_off||!gen_active||gen_layer!=0||player<0||player>=vpt::rig_count)return;
    vpt::Rig* me=&vpt::rigs[player];Vec around={me.x,me.y,me.z};
    if(mote_asset>=0)
    {
        if(!motes_seeded) { for(int i=0;i<MOTES;i++)respawn_mote(&motes[i],around,true);motes_seeded=true; }
        Vec w=wind_now();
        for(int i=0;i<MOTES;i++)
        {
            Mote* m=&motes[i];m.prev=m.p;m.age+=dt;
            m.p+=(w+(Vec){math::sin(game_time*1.7f+(float)i)*0.25f,math::sin(game_time*0.9f+(float)i*2.1f)*0.18f-0.06f,math::cos(game_time*1.3f+(float)i*0.7f)*0.25f})*dt;
            float speed=math::sqrt(vpt::dot(m.spin,m.spin));if(speed>0.01f)m.q=vpt::qmul(vpt::qaxis(m.spin/speed,speed*dt),m.q);
            float dx=m.p[0]-around[0];float dz=m.p[2]-around[2];
            if(m.age>m.life||dx*dx+dz*dz>12*12||m.p[1]<around[1]-1||vpt::solid_terrain(m.p[0],m.p[1],m.p[2])) { respawn_mote(m,around,false);continue; }
            float k=vpt::clampf(math::min(m.age/0.6f,(m.life-m.age)/0.6f),0,1);float s=m.size*k;if(s<0.004f)continue;
            vpt::Instance it={mote_asset,m.p[0],m.p[1],m.p[2],0,s,0};vpt::Instance pv={mote_asset,m.prev[0],m.prev[1],m.prev[2],0,s,0};
            int id=vpt::dyn_add(it,m.q,0x9ea4ab,true);vpt::dyn_set_prev(id,pv,m.q);
        }
    }
    if(spore_asset>=0)for(int c=0;c<3;c++)
    {
        SurfaceCave cave=surface_caves[c];Vec mouth=cave.center-cave.direction*6.5f;
        float dx=mouth[0]-me.x;float dz=mouth[2]-me.z;if(dx*dx+dz*dz>30*30)continue;
        for(int i=0;i<SPORES_PER_CAVE;i++)
        {
            float h=vpt::hash2(c*31+i,i*7+3,gen_seed+903);float h2=vpt::hash2(i*13+c,c*5+11,gen_seed+904);
            float a=h*6.2832f+game_time*(0.08f+h2*0.12f);float r=0.8f+h2*3.2f;
            float y=0.35f+h*2.1f+math::sin(game_time*(0.6f+h*0.7f)+(float)i)*0.22f;
            Vec p={mouth[0]+math::cos(a)*r,y,mouth[2]+math::sin(a)*r};float s=0.03f+0.014f*(0.5f+0.5f*math::sin(game_time*2.3f+(float)i*1.7f));
            float a0=a-(0.08f+h2*0.12f)*dt;float y0=0.35f+h*2.1f+math::sin((game_time-dt)*(0.6f+h*0.7f)+(float)i)*0.22f;
            vpt::Instance it={spore_asset,p[0],p[1],p[2],0,s,0};vpt::Instance pv={spore_asset,mouth[0]+math::cos(a0)*r,y0,mouth[2]+math::sin(a0)*r,0,s,0};
            int id=vpt::dyn_add(it,vpt::QID,i%3==0?0xf08cb4:0xc8ff6e,true);vpt::dyn_set_prev(id,pv,vpt::QID);   // 0xBBGGRR: violet / mint
        }
    }
}
