module depths;
import std::math;
import raylib6::rl;
import vpt;
import libc;

// DEPTHS main menu: save slot picker and the bestiary panel. Portraits are the creatures' static proxies
// (<rig>.vpt.json, rest pose) as raster meshes, slowly turning in an offscreen texture; undiscovered species
// are drawn as black silhouettes. Rendering happens before begin_drawing (bestiary_prepare).
Profile[SAVE_SLOTS] slot_info;   // read-only summaries for the slot picker
int bst_sel;bool erase_armed;float erase_armed_t;
vpt::Asset[SPECIES_COUNT] bst_models;bool[SPECIES_COUNT] bst_tried;
rl::RLRenderTexture2D bst_portrait;const int PORTRAIT=512;

fn void refresh_slot_info() { for(int s=0;s<SAVE_SLOTS;s++)if(!profile_read(s,&slot_info[s]))slot_info[s]={}; if(save_slot>=0)slot_info[save_slot]=profile; }
fn void choose_slot(int s)
{
    if(s==save_slot)return;profile_select(s);settings.slot=s;settings_save();refresh_slot_info();erase_armed=false;
    audio::play_sound(SND_WEAPON_LATCH,{},0.4f,1.3f,false,false,0);
}
fn ZString slot_summary(int s,bool brief=false)
{
    Profile* p=&slot_info[s];if(!p.used&&s!=save_slot)return "empty";
    if(!p.used&&!p.runs&&!total_kills(p))return "new";
    if(brief)return rl::text_format("%d/%d found",discovered_count(p),SPECIES_COUNT);
    return rl::text_format("%d/%d found  /  %d kills  /  %d runs",discovered_count(p),SPECIES_COUNT,total_kills(p),p.runs);
}
// Three slot cards (main / start panel): click = make it the active profile.
fn void slot_picker(int x,int y,int w)
{
    ui::text("SAVE SLOT",x,y,13,ui::MUTED);int cw=(w-16)/3;
    for(int s=0;s<SAVE_SLOTS;s++)
    {
        int cx=x+s*(cw+8);bool on=s==save_slot;bool hover=ui::inside((float)cx,(float)y+20,(float)cw,46);
        rl::draw_rectangle_rounded({(float)cx,(float)y+20,(float)cw,46},0.2f,6,on?(rl::RLColor){90,70,24,240}:hover?(rl::RLColor){60,56,54,230}:(rl::RLColor){34,33,32,220});
        if(on)rl::draw_rectangle_rounded_lines_ex({(float)cx,(float)y+20,(float)cw,46},0.2f,6,1.5f,ui::ACCENT);
        ZString label=rl::text_format("SLOT %d",s+1);ui::text(label,cx+(cw-ui::text_width(label,15))/2,y+25,15,on?ui::ACCENT:hover?ui::TEXT:ui::MUTED);
        ZString info=slot_summary(s,true);int fs=11;while(fs>8&&ui::text_width(info,fs)>cw-8)fs--;ui::text(info,cx+(cw-ui::text_width(info,fs))/2,y+46,fs,ui::MUTED);
        if(hover&&rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))choose_slot(s);
    }
}

// ---------------------------------------------------------------- portraits
fn vpt::Asset* bst_model(int s)
{
    if(!bst_tried[s])
    {
        bst_tried[s]=true;char[256] saved;vpt::copy_text(&saved[0],256,(ZString)&vpt::message[0]);
        if(vpt::load_asset_file(rl::text_format("assets/library/BLACK_START/%s.vpt.json",SPECIES[s].proxy),&bst_models[s]))vpt::build_model(&bst_models[s]);
        vpt::copy_text(&vpt::message[0],256,(ZString)&saved[0]);
    }
    return bst_models[s].has_model?&bst_models[s]:null;
}
fn void bestiary_prepare()
{
    if(!bst_portrait.id)bst_portrait=rl::load_render_texture(PORTRAIT,PORTRAIT);
    vpt::Asset* a=bst_model(bst_sel);
    if(a) { vpt::render_asset_view(a,bst_portrait,(float)rl::get_time()*0.45f+0.6f,{0,0,0,0}); }
    else { rl::begin_texture_mode(bst_portrait);rl::clear_background({0,0,0,0});rl::end_texture_mode(); }
}
fn void bestiary_release() { for(int s=0;s<SPECIES_COUNT;s++)if(bst_tried[s])vpt::free_asset(&bst_models[s]);if(bst_portrait.id)rl::unload_render_texture(bst_portrait); }

// Word wrap into lines of at most `w` px; returns the height used.
fn int wrapped(ZString value,int x,int y,int w,int size,rl::RLColor c)
{
    String s=value.str_view();char[256] line;int n=0;int last_space= -1;int dy=0;usz i=0;
    while(i<=s.len)
    {
        char ch=i<s.len?s[i]:0;
        if(ch==0||ch==' ')
        {
            line[n]=0;
            if(ui::text_width((ZString)&line[0],size)>w&&last_space>0)
            {
                line[last_space]=0;ui::text((ZString)&line[0],x,y+dy,size,c);dy+=size+7;
                int rest=n-last_space-1;for(int k=0;k<rest;k++)line[k]=line[last_space+1+k];n=rest;line[n]=0;
            }
            if(ch==0) { if(n)ui::text((ZString)&line[0],x,y+dy,size,c);dy+=size+7;break; }
            last_space=n;
        }
        if(n<250)line[n++]=ch;i++;
    }
    return dy;
}
fn ZString date_of(long secs)
{
    if(secs<=0)return "-";libc::Time_t t=(libc::Time_t)secs;libc::Tm tm;libc::localtime_r(&t,&tm);
    return rl::text_format("%04d-%02d-%02d",(int)tm.tm_year+1900,(int)tm.tm_mon+1,(int)tm.tm_mday);
}
fn rl::RLColor threat_color(ZString t) { String s=t.str_view();return s=="LOW"?ui::GOOD:s=="MEDIUM"?ui::ACCENT:s=="HIGH"?ui::SELECT:ui::BAD; }

// ---------------------------------------------------------------- the panel
// Returns true when the player leaves (BACK / Esc).
fn bool draw_bestiary(rl::RLRectangle view)
{
    int vw=(int)view.width;int vh=(int)view.height;Profile* p=&profile;
    rl::draw_rectangle_rec(view,{8,8,10,246});
    int x0=(int)(view.width*0.06f);int y0=(int)(view.height*0.07f);
    ui::text("BESTIARY",x0,y0,40,ui::TEXT);
    ui::text(rl::text_format("SLOT %d   /   %d of %d discovered",save_slot+1,discovered_count(p),SPECIES_COUNT),x0+4,y0+54,14,ui::MUTED);
    // slot tabs (top right): browse / switch profiles from here too
    for(int s=0;s<SAVE_SLOTS;s++) { int bx=vw-x0-3*112+s*112;if(segment(rl::text_format("SLOT %d",s+1),bx,y0+6,104,s==save_slot))choose_slot(s); }
    // list
    int ly=y0+96;int lw=math::min(320,vw/4);int rh=math::max(34,math::min(46,(vh-ly-150)/SPECIES_COUNT));
    if(rl::is_key_pressed(rl::RLKeyboardKey.DOWN)||rl::is_key_pressed(rl::RLKeyboardKey.S))bst_sel=(bst_sel+1)%SPECIES_COUNT;
    if(rl::is_key_pressed(rl::RLKeyboardKey.UP)||rl::is_key_pressed(rl::RLKeyboardKey.W))bst_sel=(bst_sel+SPECIES_COUNT-1)%SPECIES_COUNT;
    for(int s=0;s<SPECIES_COUNT;s++)
    {
        int y=ly+s*rh;bool known=p.kills[s]>0;bool on=s==bst_sel;bool hover=ui::inside((float)x0,(float)y,(float)lw,(float)rh-4);
        rl::draw_rectangle_rounded({(float)x0,(float)y,(float)lw,(float)rh-4},0.2f,6,on?(rl::RLColor){60,52,36,235}:hover?(rl::RLColor){44,42,40,220}:(rl::RLColor){24,24,26,200});
        if(on)rl::draw_rectangle(x0,y+6,3,rh-16,ui::ACCENT);
        ui::text(rl::text_format("%02d",s+1),x0+12,y+(rh-4)/2-8,12,{110,102,96,255});
        ui::text(known?SPECIES[s].name:"? ? ?",x0+40,y+(rh-4)/2-9,15,known?(on?ui::ACCENT:ui::TEXT):(rl::RLColor){110,102,96,255});
        if(known) { ZString k=rl::text_format("%d",p.kills[s]);ui::text(k,x0+lw-14-ui::text_width(k,13),y+(rh-4)/2-8,13,ui::MUTED); }
        if(hover&&rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))bst_sel=s;
    }
    // portrait
    int s=bst_sel;bool known=p.kills[s]>0;
    int px=x0+lw+40;int box=math::min(math::min(460,vh-ly-150),(vw-px-x0)/2);int py=ly;
    rl::draw_rectangle_rounded({(float)px,(float)py,(float)box,(float)box},0.04f,6,{30,28,27,235});
    rl::draw_rectangle_gradient_v(px,py+box*2/3,box,box/3,{30,28,27,0},{48,40,30,200});
    if(bst_portrait.id)rl::draw_texture_pro(bst_portrait.texture,{0,0,(float)PORTRAIT,-(float)PORTRAIT},{(float)px,(float)py,(float)box,(float)box},{0,0},0,known?rl::WHITE:(rl::RLColor){6,6,8,255});
    if(!known) { ZString q="?";ui::text(q,px+box/2-ui::text_width(q,72)/2,py+box/2-44,72,{70,64,60,255}); }
    if(s==SP_BROOD&&known)ui::text("x1.6",px+box-50,py+box-28,14,ui::MUTED);
    // details
    int dx=px+box+36;int dw=vw-x0-dx;int y=py;
    ui::text(known?SPECIES[s].name:"UNKNOWN SPECIES",dx,y,30,known?ui::TEXT:ui::MUTED);y+=46;
    ui::text(SPECIES[s].habitat,dx,y,14,ui::MUTED);y+=30;
    if(known)
    {
        ui::text("THREAT",dx,y,12,ui::MUTED);ui::text(SPECIES[s].threat,dx+70,y-1,14,threat_color(SPECIES[s].threat));
        ui::text("HIT POINTS",dx+180,y,12,ui::MUTED);ui::text(rl::text_format("%d",SPECIES[s].hp),dx+280,y-1,14,ui::TEXT);y+=34;
        ui::text(rl::text_format("%d",p.kills[s]),dx,y,44,ui::ACCENT);ui::text("KILLED",dx+8+ui::text_width(rl::text_format("%d",p.kills[s]),44),y+24,13,ui::MUTED);y+=68;
        // per mech
        int most=1;for(int m=0;m<ROBOT_COUNT;m++)most=math::max(most,p.by_mech[s*ROBOT_COUNT+m]);
        const ZString[ROBOT_COUNT] SHORT={"RATTLER","MORTAR","MAUL"};
        for(int m=0;m<ROBOT_COUNT;m++)
        {
            int n=p.by_mech[s*ROBOT_COUNT+m];int bw=math::max(40,dw-170);
            ui::text(SHORT[m],dx,y,13,ui::MUTED);rl::draw_rectangle_rounded({(float)dx+80,(float)y+3,(float)bw,8},0.5f,4,{50,46,44,255});
            if(n)rl::draw_rectangle_rounded({(float)dx+80,(float)y+3,(float)bw*(float)n/(float)most,8},0.5f,4,ui::ACCENT);
            ui::text(rl::text_format("%d",n),dx+90+bw,y,13,ui::TEXT);y+=24;
        }
        y+=10;
        ui::text("KILLED YOU",dx,y,12,ui::MUTED);ui::text(rl::text_format("%d",p.killed_you[s]),dx+100,y-1,14,p.killed_you[s]?ui::BAD:ui::TEXT);
        ui::text("FIRST KILL",dx+180,y,12,ui::MUTED);ui::text(date_of(p.first[s]),dx+270,y-1,14,ui::TEXT);y+=36;
        rl::draw_rectangle(dx,y,dw,1,{70,64,60,255});y+=16;
        y+=wrapped(SPECIES[s].lore,dx,y,dw,15,ui::TEXT);
    }
    else
    {
        ui::text("Kill one to learn more.",dx,y,16,ui::MUTED);y+=30;
        if(p.killed_you[s]) { ui::text(rl::text_format("It has killed you %d time%s.",p.killed_you[s],p.killed_you[s]==1?"":"s"),dx,y,15,ui::BAD); }
    }
    // profile totals
    int by=vh-(int)(view.height*0.07f)-40;
    int hours=(int)(p.play_time/3600);int mins=(int)(p.play_time/60)%60;
    ui::text(rl::text_format("RUNS %d     DEATHS %d     DEEPEST LAYER %d     KILLS %d     TIME PLAYED %dh %02dm",p.runs,p.deaths,-p.deepest,total_kills(p),hours,mins),px,by+14,14,ui::MUTED);
    bool back=big_button("BACK",x0,by,lw-10)||rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE);
    // erase this slot (click twice)
    erase_armed_t-=rl::get_frame_time();if(erase_armed_t<=0)erase_armed=false;
    ZString el=erase_armed?"CLICK AGAIN TO ERASE":"ERASE SLOT";int ew=ui::text_width(el,13)+28;int ex=vw-x0-ew;
    bool eh=ui::inside((float)ex,(float)by+8,(float)ew,30);
    rl::draw_rectangle_rounded({(float)ex,(float)by+8,(float)ew,30},0.3f,4,erase_armed?(rl::RLColor){120,30,24,240}:eh?(rl::RLColor){60,40,36,230}:(rl::RLColor){34,33,32,200});
    ui::text(el,ex+14,by+16,13,erase_armed||eh?ui::BAD:ui::MUTED);
    if(eh&&rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
    {
        if(erase_armed) { profile_erase(save_slot);refresh_slot_info();erase_armed=false;audio::play_sound(SND_WEAPON_WHIR,{},0.5f,0.7f,false,false,0); }
        else { erase_armed=true;erase_armed_t=3; }
    }
    return back;
}
