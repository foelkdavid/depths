module depths;
import std::math;
import raylib6::rl;
import vpt;

// Third-person play camera (V in game). The mouse is captured: moving it turns the camera, and the robot
// aims (turns its body) along the crosshair at the screen centre. WASD walks relative to the camera.
// The camera trails over the right shoulder on a spring arm: a ray from the robot to the wanted camera spot
// pulls the camera in front of walls, but never closer than 2 m; whatever still lies between lens and robot
// (rock when pinned, roof, creatures) is cut away for primary rays in the tracer (camCut) and creatures in the
// way are dithered (rig_cutaway). Position follows with exponential smoothing.

bool third_person;
// Mode switch swoosh: the rendered camera flies from the old view to the new one (ease in/out, lifted on an arc).
float cam_blend=1;rl::RLCamera3D cam_from;rl::RLCamera3D last_cam;const float SWOOSH_TIME=0.7f;
fn rl::RLCamera3D swoosh(rl::RLCamera3D to,float dt)
{
    if(cam_blend>=1) { last_cam=to;return to; }
    cam_blend=math::min(1.0f,cam_blend+dt/SWOOSH_TIME);float t=cam_blend*cam_blend*(3-2*cam_blend);
    rl::RLCamera3D c=to;
    c.position=cam_from.position+(to.position-cam_from.position)*t+(rl::RLVector3){0,math::sin(t*3.14159f)*3.0f,0};
    c.target=cam_from.target+(to.target-cam_from.target)*t;c.fovy=cam_from.fovy+(to.fovy-cam_from.fovy)*t;
    c.projection=rl::RLCameraProjection.PERSPECTIVE;last_cam=c;return c;
}
float tp_yaw;float tp_pitch=0.4f;
rl::RLCamera3D tp_last_cam;   // the third-person camera of the last frame: the crosshair ray comes from it
rl::RLVector3 tp_pivot;float tp_arm;rl::RLVector2 tp_mouse;bool tp_snap=true;bool tp_captured;
const float TP_DISTANCE=4.8f;const float TP_HEIGHT=1.5f;const float TP_SHOULDER=0.45f;const float TP_FOV=55;
const float TP_SENS=0.0016f;const float TP_MIN_ARM=2.0f;

fn rl::RLVector3 tp_forward() => {math::sin(tp_yaw),0,math::cos(tp_yaw)};
fn rl::RLVector3 tp_right() => {-math::cos(tp_yaw),0,math::sin(tp_yaw)};
fn rl::RLVector3 tp_dir() => {math::sin(tp_yaw)*math::cos(tp_pitch),-math::sin(tp_pitch),math::cos(tp_yaw)*math::cos(tp_pitch)};

fn void toggle_third_person()
{
    third_person=!third_person;tp_snap=true;tp_mouse={};cam_blend=0;cam_from=last_cam;
    if(vpt::controlled_rig>=0&&vpt::controlled_rig<vpt::rig_count)tp_yaw=vpt::rigs[vpt::controlled_rig].yaw;
    vpt::report(third_person?"Third person: mouse turns + aims, WASD walks, left mouse fires. V: back to top-down.":"Top-down view. V: third person.");
}
// Mouse capture follows the state every frame (Esc / F2 / dialogs / leaving play release it).
fn void tp_update_capture(bool want)
{
    if(want==tp_captured)return;tp_captured=want;
    if(want) { rl::disable_cursor();tp_snap=true;tp_mouse={}; } else { rl::enable_cursor(); }
}
fn bool tp_active() => game_on&&third_person&&tp_captured;
// Mouse look + WASD (called once per frame while active). The mouse delta is lightly smoothed (one-frame
// spikes from relative pointer events made the view jerk) and clamped; the view itself turns with no lag.
fn void tp_input(float dt)
{
    rl::RLVector2 d=rl::get_mouse_delta();d[0]=vpt::clampf(d[0],-120,120);d[1]=vpt::clampf(d[1],-120,120);
    float k=1-math::exp(-dt*45);tp_mouse+=(d-tp_mouse)*k;if(tp_snap)tp_mouse={};
    tp_yaw-=tp_mouse[0]*TP_SENS;tp_pitch=vpt::clampf(tp_pitch+tp_mouse[1]*TP_SENS*0.8f,-0.75f,0.85f);   // negative: looking up at the cave roof
    float a=(rl::is_key_down(rl::RLKeyboardKey.D)?1.0f:0)-(rl::is_key_down(rl::RLKeyboardKey.A)?1.0f:0);
    float b=(rl::is_key_down(rl::RLKeyboardKey.W)?1.0f:0)-(rl::is_key_down(rl::RLKeyboardKey.S)?1.0f:0);
    rl::RLVector3 v=tp_right()*a+tp_forward()*b;float l=math::sqrt(vpt::dot(v,v));
    vpt::control_input=l>1?v/l:v;
}
// Camera = smoothed follow point + exact orbit. Only the follow point lags (soft in x/z, softer in y so steps,
// knock-back and terrain bumps don't bob the view); rotation is exact, so the robot never swims on screen.
// Spring arm: an obstruction shortens the arm at once, freeing it lets it grow back smoothly.
// Arm length in front of a hit: 0.4 m clearance, but never past the hit itself (a 0.4 m minimum put the lens
// inside the wall when the robot was pinned against it: a black screen).
fn float arm_before(float d) => d>0.8f?d-0.4f:d*0.5f;
fn rl::RLCamera3D tp_camera(vpt::Rig r,float dt)
{
    rl::RLVector3 raw={r.x,r.y+TP_HEIGHT,r.z};
    if(tp_snap) { tp_pivot=raw;tp_arm=TP_DISTANCE; }
    else
    {
        float kx=1-math::exp(-dt*9);float ky=1-math::exp(-dt*4);
        tp_pivot[0]+=(raw[0]-tp_pivot[0])*kx;tp_pivot[2]+=(raw[2]-tp_pivot[2])*kx;tp_pivot[1]+=(raw[1]-tp_pivot[1])*ky;
    }
    // Shoved into a wall, the follow point can end up inside rock: drop it toward the robot until it is free.
    rl::RLVector3 pivot=tp_pivot;
    for(int k=0;k<6&&vpt::solid_terrain(pivot[0],pivot[1],pivot[2]);k++)pivot=(rl::RLVector3){r.x,r.y+TP_HEIGHT*(1-(float)k*0.15f),r.z};
    rl::RLVector3 dir=tp_dir();rl::RLVector3 back=vpt::normalized(tp_right()*(TP_SHOULDER/TP_DISTANCE)-dir);
    vpt::pick_floor=true;vpt::Pick hit=vpt::world_pick({pivot,back});vpt::pick_floor=false;   // floor slabs stop the arm too (looking up)
    float reach=TP_DISTANCE;if(hit.hit&&hit.distance<TP_DISTANCE+0.4f)reach=arm_before(hit.distance);
    // Pinned against a wall (a boss shoving you, a tight tunnel) the arm keeps 2 m: the rock between lens and robot
    // is cut away per voxel in the tracer (camCut) instead of the camera collapsing into the hull / the wall.
    reach=math::max(reach,TP_MIN_ARM);
    // Pull-in is fast but smooth now (whatever lies between is cut away, so a lag never hides the robot).
    if(tp_snap) { tp_arm=reach; } else { tp_arm+=(reach-tp_arm)*(1-math::exp(-dt*(reach<tp_arm?10:3))); }
    tp_snap=false;
    rl::RLVector3 pos=pivot+back*tp_arm;pos[1]=math::max(pos[1],0.35f);
    for(int k=0;k<8&&vpt::solid_terrain(pos[0],pos[1],pos[2]);k++)pos+=(pivot-pos)*0.3f;   // never render from inside rock
    tp_last_cam={.position=pos,.target=pos+dir*10,.up={0,1,0},.fovy=TP_FOV,.projection=rl::RLCameraProjection.PERSPECTIVE};
    tp_fade_occluders(pos,{r.x,r.y+0.5f,r.z},dt);
    vpt::cam_cut_a=pos;vpt::cam_cut_b={r.x,r.y+0.55f,r.z};vpt::cam_cut_radius=0.95f;
    return tp_last_cam;
}
// Creatures between the camera and the robot (or at the lens) turn screen-door see-through for the camera only:
// a boss charging the robot used to fill the whole view, or put the camera inside its body. Shadows, light and
// shots are unaffected. Each rig is a sphere around its posed parts.
fn void tp_fade_occluders(rl::RLVector3 eye,rl::RLVector3 robot,float dt)
{
    float[vpt::MAX_RIGS] reach;rl::RLVector3[vpt::MAX_RIGS] mid;int[vpt::MAX_RIGS] n;
    for(int r=0;r<vpt::rig_count;r++) { reach[r]=0;mid[r]={};n[r]=0; }
    for(int k=0;k<vpt::rig_part_count;k++) { int o=vpt::rig_part_owner[k];if(o<0||o>=vpt::rig_count)continue;mid[o]+=(rl::RLVector3){vpt::rig_parts[k].x,vpt::rig_parts[k].y,vpt::rig_parts[k].z};n[o]++; }
    for(int r=0;r<vpt::rig_count;r++)if(n[r])mid[r]/=(float)n[r];
    for(int k=0;k<vpt::rig_part_count;k++)
    {
        int o=vpt::rig_part_owner[k];if(o<0||o>=vpt::rig_count)continue;vpt::Instance p=vpt::rig_parts[k];
        rl::RLVector3 d={p.x,p.y,p.z};d-=mid[o];float pr=vpt::assets[p.asset].size*(float)math::max(vpt::assets[p.asset].dx,math::max(vpt::assets[p.asset].dy,vpt::assets[p.asset].dz))*p.scale*0.6f;
        reach[o]=math::max(reach[o],math::sqrt(vpt::dot(d,d))+pr);
    }
    rl::RLVector3 seg=robot-eye;float len2=math::max(vpt::dot(seg,seg),0.0001f);
    for(int r=0;r<vpt::rig_count;r++)
    {
        float want=0;
        if(r==vpt::controlled_rig&&n[r]) { rl::RLVector3 e=eye-mid[r];if(math::sqrt(vpt::dot(e,e))<reach[r]+0.35f)want=0.6f; }   // lens inside the robot
        else if(n[r])
        {
            float t=vpt::clampf(vpt::dot(mid[r]-eye,seg)/len2,0,1);rl::RLVector3 c=eye+seg*t-mid[r];float d=math::sqrt(vpt::dot(c,c));
            rl::RLVector3 e=eye-mid[r];float de=math::sqrt(vpt::dot(e,e));
            if(d<reach[r]*0.85f||de<reach[r]+0.6f)want=0.85f;
        }
        vpt::rig_cutaway[r]+=(want-vpt::rig_cutaway[r])*(1-math::exp(-dt*(want>vpt::rig_cutaway[r]?14:6)));
    }
}
fn void tp_clear_fade() { for(int r=0;r<vpt::MAX_RIGS;r++)vpt::rig_cutaway[r]=0;vpt::cam_cut_radius=0; }
// The main loop rebuilds `cam` from the editor orbit every frame, so aim from the remembered third-person camera
// (aiming from the orbit camera put the target under the robot: it never turned).
fn rl::RLRay tp_aim_ray() => {tp_last_cam.position,vpt::normalized(tp_last_cam.target-tp_last_cam.position)};
fn void tp_draw_crosshair(rl::RLRectangle view)
{
    int cx=(int)(view.x+view.width/2);int cy=(int)(view.y+view.height/2);rl::RLColor c={235,219,178,220};
    rl::draw_rectangle(cx-11,cy-1,7,2,c);rl::draw_rectangle(cx+5,cy-1,7,2,c);rl::draw_rectangle(cx-1,cy-11,2,7,c);rl::draw_rectangle(cx-1,cy+5,2,7,c);
    rl::draw_rectangle(cx-1,cy-1,2,2,{251,73,52,230});
}
