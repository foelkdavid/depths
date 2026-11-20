module depths;
import std::math;
import std::encoding::json;
import raylib6::rl;
import vpt;
import libc;

// Game settings, saved to ~/.config/vpt-game.json. Applied every frame (layer generation resets lighting).
struct Settings { int quality;int bounces;bool pixel_lights;bool fullscreen;float volume;bool show_fps;int robot;int slot; }   // robot: ROBOT_RIGS index, slot: active save slot
Settings settings={2,2,false,false,0.8f,false,0,0};
const float[3] QUALITY_SCALE={0.5f,0.75f,1.0f};
const ZString[3] QUALITY_NAMES={"LOW","MEDIUM","HIGH"};
bool fullscreen_now;

fn ZString settings_path()
{
    ZString home=libc::getenv("HOME");
    return home?rl::text_format("%s/.config/vpt-game.json",home):"vpt-game.json";
}
fn void settings_load()
{
    ZString path=settings_path();if(!rl::file_exists(path))return;
    char* text=rl::load_file_text(path);if(!text)return;defer rl::unload_file_text((ZString)text);
    if(try s=json::unmarshal(tmem,((ZString)text).str_view(),Settings))
    {
        settings=s;settings.quality=math::clamp(settings.quality,0,2);settings.bounces=math::clamp(settings.bounces,1,3);
        settings.volume=math::is_finite(settings.volume)?vpt::clampf(settings.volume,0,1):0.8f;settings.robot=math::clamp(settings.robot,0,ROBOT_COUNT-1);settings.slot=math::clamp(settings.slot,0,SAVE_SLOTS-1);
    }
}
fn void settings_save()
{
    ZString home=libc::getenv("HOME");if(home)(void)rl::make_directory(rl::text_format("%s/.config",home));
    (void)rl::save_file_text(settings_path(),rl::text_format("{\"quality\":%d,\"bounces\":%d,\"pixel_lights\":%s,\"fullscreen\":%s,\"volume\":%.2f,\"show_fps\":%s,\"robot\":%d,\"slot\":%d}\n",
        settings.quality,settings.bounces,settings.pixel_lights?"true":"false",settings.fullscreen?"true":"false",(double)settings.volume,settings.show_fps?"true":"false",settings.robot,settings.slot));
}
fn void settings_apply()
{
    vpt::lighting.quality=QUALITY_SCALE[settings.quality];vpt::lighting.bounces=settings.bounces;
    vpt::lighting.light_pixel=settings.pixel_lights?0.125f:0;audio::master=settings.volume;
    if(settings.fullscreen!=fullscreen_now) { rl::toggle_borderless_windowed();fullscreen_now=settings.fullscreen; }
}
