module depths;
import std::math;
import raylib6::rl;
import vpt;

// Generation happens between update and pose/render, never during a hit/rig-removal loop.
Vec portal_base;int portal_frame= -1;int portal_particle_asset= -1;bool portal_exists;bool portal_armed;
float portal_age;float portal_fade;float arrival_time;bool layer_pending;bool coming_soon;
vpt::Instance[160] portal_previous;vpt::Quat[160] portal_previous_q;int portal_previous_count;int portal_particle_index;
fn bool is_layer_boss(int r) => r>=0&&r<vpt::rig_count&&(kind[r]==CRAWLER||kind[r]==STALKER)&&vpt::rigs[r].scale>1.3f;
fn void progression_init()
{
    portal_exists=false;portal_armed=false;portal_age=0;portal_fade=0;layer_pending=false;coming_soon=false;arrival_time=1.6f;portal_frame= -1;
    portal_previous_count=0;
    if(!gen_active)return;
    for(int r=0;r<vpt::rig_count;r++)if(is_layer_boss(r))
    {
        vpt::Rig* e=&vpt::rigs[r];portal_base={e.x,e.y,e.z-(gen_layer==0&&surface_cave_at(e.x,e.z)>=0?3.0f:4.5f)};
        if(gen_layer== -1&&vpt::blocked(portal_base[0],portal_base[2],e.y,1.1f))portal_base={e.x,e.y,e.z};
        portal_base[1]=gen_layer==0?surface_walk_height(portal_base[0],portal_base[2]):vpt::ground_at(portal_base,e.y);portal_exists=true;break;
    }
    if(portal_exists)
    {
        portal_particle_asset=vpt::make_cube_asset("rift-ion",1,0xffffff,0.2f);
        if(portal_particle_asset>=0)vpt::pinned_assets[portal_particle_asset]=true;
        portal_frame=vpt::import_asset("assets/library/BLACK_START/rift-monument.vpt.json");
        if(portal_frame>=0)vpt::pinned_assets[portal_frame]=true;
    }
}
fn void unlock_layer_exit()
{
    if(layer_clear)return;layer_clear=true;portal_age=0;portal_armed=false;portal_previous_count=0;
    if(!gen_active||!portal_exists) { vpt::report("Boss defeated.");return; }
    flash(portal_base+(Vec){0,1.4f,0},{20,100,180},9,1.0f);
    popup_title="RIFT AWAKENED";popup_info=gen_layer==0?"walk into the rift to descend to layer -1":"walk into the rift: layer -2 is coming soon";popup_color=0xffdc60;popup_t=POPUP_TIME;
    vpt::report(gen_layer==0?"SURFACE BOSS DEFEATED. The rift is awake. Walk through to descend to layer -1.":"CAVE BOSS DEFEATED. The rift is awake. Layer -2: coming soon.");
}
fn void progression_update(float dt)
{
    arrival_time=math::max(0.0f,arrival_time-dt);
    if(!portal_exists||!layer_clear||game_over||coming_soon)return;
    portal_age+=dt;
    if(portal_fade>0)
    {
        vpt::control_input={};portal_fade+=dt;
        if(portal_fade>=0.9f)
        {
            if(gen_layer==0) { layer_pending=true; }
            else { coming_soon=true;portal_fade=0;vpt::report("LAYER -2: COMING SOON. Surface and caves conquered. R: new expedition."); }
        }
        return;
    }
    if(player<0||player>=vpt::rig_count)return;
    vpt::Rig* me=&vpt::rigs[player];Vec dv=(Vec){me.x,me.y,me.z}-portal_base;dv[1]=0;
    float ds=vpt::dot(dv,dv);if(ds>5)portal_armed=true;
    if(portal_armed&&portal_age>2&&ds<1.1f&&math::abs(me.y-portal_base[1])<1.5f)
    {
        portal_fade=0.001f;vpt::control_input={};
        for(int r=0;r<vpt::rig_count;r++) { vpt::Rig* e=&vpt::rigs[r];e.held=true;e.hunting=false;e.patrol=false;e.velocity={}; }
        play_teleport();
    }
}
int cheat_layer= -9;   // F2 layer jump, applied here (between game_update and update_rigs) like a rift crossing
fn void apply_layer_transition()
{
    if(cheat_layer> -9)
    {
        int target=cheat_layer;cheat_layer= -9;
        SkillState carried=skills_save();float hull=player_hp;int carried_keys=keys;bool view=third_person;
        play_generated(0,true,target);if(!game_on)return;
        skills_load(carried);player_hp=hull;keys=carried_keys;third_person=view;tp_snap=true;cam_blend=1;cheat_open=false;
        popup_title=target==0?"LAYER 0 / THE ASH WASTE":"LAYER -1 / THE HOLLOW";popup_info="cheat: layer jump";popup_color=0xc872ce;popup_t=POPUP_TIME;
        return;
    }
    if(!layer_pending)return;layer_pending=false;
    SkillState carried=skills_save();float hull=player_hp;bool aim=auto_aim;bool invulnerable=god;int carried_keys=keys;
    float warp_cursor=teleport_resume_cursor();
    bool view=third_person;uint seed=gen_seed*1664525u+1013904223u;if(!seed)seed=1;
    play_generated(seed,true,-1);
    if(!game_on)return;
    skills_load(carried);player_hp=hull;auto_aim=aim;god=invulnerable;keys=carried_keys;third_person=view;tp_snap=true;cam_blend=1;
    play_teleport(warp_cursor);   // continue the cue's tail on arrival, don't restart the entire sound
    arrival_time=2;popup_title="LAYER -1 / THE HOLLOW";popup_info="beneath the salt: living rock, nests and cave aliens";popup_color=0xc872ce;popup_t=POPUP_TIME;
}
fn void portal_cube(Vec p,float size,uint color,vpt::Quat q)
{
    vpt::Instance now={portal_particle_asset,p[0],p[1]-size*0.5f,p[2],0,size,0};int id=vpt::dyn_add(now,q,color,true);
    int k=portal_particle_index++;if(k>=160)return;
    vpt::dyn_set_prev(id,k<portal_previous_count?portal_previous[k]:now,k<portal_previous_count?portal_previous_q[k]:q);
    portal_previous[k]=now;portal_previous_q[k]=q;
}
fn void progression_draw()
{
    if(!gen_active)return;portal_particle_index=0;
    if(portal_exists&&portal_frame>=0&&layer_clear)
    {
        // Manifest only after the boss dies. A destroyed dormant placed monument stays destroyed until then.
        for(int i=0;i<vpt::instance_count;i++)if(((ZString)&vpt::assets[vpt::instances[i].asset].path[0]).str_view().ends_with("rift-monument.vpt.json"))vpt::hidden[i]=true;
        vpt::Instance frame={portal_frame,portal_base[0],portal_base[1],portal_base[2],0,1,0};int id=vpt::dyn_add(frame,vpt::QID);vpt::dyn_set_prev(id,frame,vpt::QID);
    }
    if(portal_exists&&layer_clear)
    {
        float charge=vpt::smooth(0,1.6f,portal_age);float time=game_time;Vec center=portal_base+(Vec){0,1.65f,0};
        // Counter-rotating broken rings, three intertwined vortex arms, upward ion motes and a floor halo.
        for(int k=0;k<36;k++)
        {
            float a=(float)k*6.2831853f/36+time*0.8f;float r=1.28f*charge;
            Vec p=center+(Vec){math::cos(a)*r,math::sin(a)*r,math::sin(a*3+time)*0.05f};
            portal_cube(p,0.12f+0.025f*math::sin(time*3+(float)k),k%3==0?0xff70c0:0xffdc60,vpt::qaxis({0,0,1},a));
        }
        for(int arm=0;arm<3;arm++)for(int k=0;k<14;k++)
        {
            float f=(float)k/14;float a=f*5.3f-time*1.9f+(float)arm*2.0944f;float r=(0.08f+f*1.02f)*charge;
            portal_cube(center+(Vec){math::cos(a)*r,math::sin(a)*r,0.08f*math::sin(a*2+time)},0.08f+f*0.07f,arm==1?0xff70c0:0xffe9ac,vpt::qaxis({0,0,1},-a));
        }
        for(int k=0;k<18;k++)
        {
            float phase=(float)k*0.618034f+time*0.28f;phase-=math::floor(phase);float a=(float)k*2.399963f+time;
            Vec p=portal_base+(Vec){math::cos(a)*(1.8f-phase*0.4f)*charge,phase*3.8f,math::sin(a)*0.65f};
            portal_cube(p,0.045f+(1-phase)*0.025f,0xffdc60,vpt::qaxis({1,1,0},a));
        }
        for(int k=0;k<16;k++)
        { float a=(float)k*0.392699f-time*0.4f;portal_cube(portal_base+(Vec){math::cos(a)*1.8f,0.08f,math::sin(a)*1.8f},0.09f,0xff70c0,vpt::qaxis({0,1,0},a)); }
        vpt::game_light(center,{8*charge,30*charge,48*charge},7);
    }
    if(arrival_time>0&&player>=0&&player<vpt::rig_count)
    {
        vpt::Rig* me=&vpt::rigs[player];float f=vpt::clampf(arrival_time/2,0,1);
        for(int k=0;k<18;k++)
        {
            float a=(float)k*2.399963f+game_time*4;float r=f*(0.6f+(float)(k%4)*0.15f);
            portal_cube((Vec){me.x+math::cos(a)*r,me.y+0.25f+(float)(k%6)*0.17f,me.z+math::sin(a)*r},0.055f*f,0xffdc60,vpt::qaxis({0,1,0},a));
        }
    }
    portal_previous_count=portal_particle_index;
}
fn void progression_hud(rl::RLRectangle view)
{
    if(!gen_active)return;
    ui::text(gen_layer==0?"LAYER 0  /  THE ASH WASTE":"LAYER -1  /  THE HOLLOW",(int)view.x+18,(int)view.y+18,16,gen_layer==0?(rl::RLColor){221,189,125,255}:(rl::RLColor){193,132,201,255});
    if(layer_clear&&!coming_soon)
    {
        ui::text(gen_layer==0?"RIFT OPEN  /  descend to -1":"RIFT OPEN  /  -2 coming soon",(int)view.x+18,(int)(view.y+view.height)-64,14,{114,220,235,255});
        if(player>=0&&player<vpt::rig_count)
        { Vec dv=portal_base-(Vec){vpt::rigs[player].x,0,vpt::rigs[player].z};ui::text(rl::text_format("%.0f m to rift",math::sqrt(dv[0]*dv[0]+dv[2]*dv[2])),(int)view.x+18,(int)(view.y+view.height)-84,13,ui::MUTED); }
    }
    float fade=portal_fade>0?vpt::clampf(portal_fade/0.9f,0,1):arrival_time>1?vpt::clampf((arrival_time-1)/0.8f,0,1):0;
    if(fade>0)rl::draw_rectangle_rec(view,{118,214,235,(char)(int)(fade*230)});
    if(coming_soon)
    {
        rl::draw_rectangle_rec(view,{12,14,20,220});int cx=(int)(view.x+view.width*0.5f);int cy=(int)(view.y+view.height*0.5f);
        ui::text("LAYER -2",cx-ui::text_width("LAYER -2",38)/2,cy-48,38,{121,224,235,255});
        ui::text("COMING SOON",cx-ui::text_width("COMING SOON",24)/2,cy+4,24,ui::TEXT);
        ui::text("Surface and caves conquered.  R: new expedition",cx-ui::text_width("Surface and caves conquered.  R: new expedition",16)/2,cy+48,16,ui::MUTED);
    }
}
