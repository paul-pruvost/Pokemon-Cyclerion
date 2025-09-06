#===============================================================================#
# Delta Speed Up v21.1 - Full script avec HUD
#===============================================================================#

module Settings
  SPEED_OPTIONS = true
end

SPEEDUP_STAGES = [1.0, 2.0, 3.0]
$GameSpeed = 0
$CanToggle = true
$RefreshEventsForTurbo = false

#===============================================================================#
# Game load
#===============================================================================#
module Game
  class << self
    alias_method :original_load, :load unless method_defined?(:original_load)
  end

  def self.load(save_data)
    original_load(save_data)
    $CanToggle = $PokemonSystem.only_speedup_battles == 0
  end
end

#===============================================================================#
# Input handling
#===============================================================================#
module Input
  class << self
    alias_method :delta_speedup_update, :update unless method_defined?(:delta_speedup_update)
  end

  def self.update
    delta_speedup_update
    if $CanToggle && trigger?(Input::AUX1)
      $GameSpeed += 1
      $GameSpeed = 0 if $GameSpeed >= SPEEDUP_STAGES.size
      $PokemonSystem.battle_speed = $GameSpeed if $PokemonSystem && $PokemonSystem.only_speedup_battles == 1
      $RefreshEventsForTurbo = true
      echoln "[Delta Speed Up] Speed changed: x#{SPEEDUP_STAGES[$GameSpeed]} (#{$GameSpeed})"
    end
  end
end

#===============================================================================#
# System uptime
#===============================================================================#
module System
  class << self
    alias_method :unscaled_uptime, :uptime unless method_defined?(:unscaled_uptime)
  end

  def self.uptime
    SPEEDUP_STAGES[$GameSpeed] * unscaled_uptime
  end
end

#===============================================================================#
# Battle speed handlers
#===============================================================================#
# Démarrage de combat : appliquer la vitesse mémorisée si "Battles Only",
# et laisser le toggle actif pendant tout le combat.
EventHandlers.add(:on_start_battle, :start_speedup, proc {
  if $PokemonSystem.only_speedup_battles == 1
    $GameSpeed = $PokemonSystem.battle_speed
  end
})

# Fin de combat : en "Battles Only", on revient à x1.0
EventHandlers.add(:on_end_battle, :stop_speedup, proc {
  if $PokemonSystem.only_speedup_battles == 1
    $GameSpeed = 0
  end
})


# class Battle
#   alias_method :original_pbCommandPhase, :pbCommandPhase unless method_defined?(:original_pbCommandPhase)
#   def pbCommandPhase
#     $CanToggle = true
#     original_pbCommandPhase
#     $CanToggle = false
#   end
# end

#===============================================================================#
# Event fixes
#===============================================================================#
alias :original_pbBattleOnStepTaken :pbBattleOnStepTaken
def pbBattleOnStepTaken(repel_active)
  return if $game_temp.in_battle
  original_pbBattleOnStepTaken(repel_active)
end

class Game_Event < Game_Character
  def pbGetInterpreter
    return @interpreter
  end

  def pbResetInterpreterWaitCount
    @interpreter.pbRefreshWaitCount if @interpreter && @trigger == 4
  end
end

class Interpreter
  def pbRefreshWaitCount
    @wait_count = 0
    @wait_start = System.uptime
  end
end

class Window_AdvancedTextPokemon < SpriteWindow_Base
  def pbResetWaitCounter
    @wait_timer_start = nil
    @waitcount = 0
    @display_last_updated = nil
  end
end

$CurrentMsgWindow = nil
def pbMessage(message, commands = nil, cmdIfCancel = 0, skin = nil, defaultCmd = 0, &block)
  ret = 0
  msgwindow = pbCreateMessageWindow(nil, skin)
  $CurrentMsgWindow = msgwindow

  if commands
    ret = pbMessageDisplay(msgwindow, message, true,
      proc { |msgwndw|
        next Kernel.pbShowCommands(msgwndw, commands, cmdIfCancel, defaultCmd, &block)
      }, &block)
  else
    pbMessageDisplay(msgwindow, message, &block)
  end
  pbDisposeMessageWindow(msgwindow)
  $CurrentMsgWindow = nil
  Input.update
  return ret
end

#===============================================================================#
# Map & fog fixes
#===============================================================================#
class Game_Map
  alias_method :original_update, :update unless method_defined?(:original_update)

  def update
    if $RefreshEventsForTurbo
      echoln "UNSCALED #{System.unscaled_uptime} * #{SPEEDUP_STAGES[$GameSpeed]} - #{$GameSpeed}"
      $game_map.events.each_value { |event| event.pbResetInterpreterWaitCount } if $game_map&.events
      @scroll_timer_start = System.uptime/SPEEDUP_STAGES[SPEEDUP_STAGES.size-1] if (@scroll_distance_x || 0) != 0 || (@scroll_distance_y || 0) != 0
      $CurrentMsgWindow.pbResetWaitCounter if $game_temp.message_window_showing && $CurrentMsgWindow
      $RefreshEventsForTurbo = false
    end

    temp_timer = @fog_scroll_last_update_timer
    @fog_scroll_last_update_timer = System.uptime
    original_update
    @fog_scroll_last_update_timer = temp_timer
    update_fog
  end

  def update_fog
    uptime_now = System.unscaled_uptime
    @fog_scroll_last_update_timer ||= uptime_now
    speedup_mult = $PokemonSystem.only_speedup_battles == 1 ? 1 : SPEEDUP_STAGES[$GameSpeed]
    scroll_mult = (uptime_now - @fog_scroll_last_update_timer) * 5 * speedup_mult
    @fog_ox -= @fog_sx * scroll_mult
    @fog_oy -= @fog_sy * scroll_mult
    @fog_scroll_last_update_timer = uptime_now
  end
end

#===============================================================================#
# Animation fix
#===============================================================================#
class SpriteAnimation
  def update_animation
    new_index = ((System.uptime - @_animation_timer_start) / @_animation_time_per_frame).to_i
    if new_index >= @_animation_duration
      dispose_animation
      return
    end
    quick_update = (@_animation_index == new_index)
    @_animation_index = new_index
    frame_index = @_animation_index
    current_frame = @_animation.frames[frame_index]
    unless current_frame
      dispose_animation
      return
    end
    cell_data   = current_frame.cell_data
    position    = @_animation.position
    animation_set_sprites(@_animation_sprites, cell_data, position, quick_update)
    return if quick_update
    @_animation.timings.each do |timing|
      next if timing.frame != frame_index
      animation_process_timing(timing, @_animation_hit)
    end
  end
end

#===============================================================================#
# PokemonSystem accessors
#===============================================================================#
class PokemonSystem
  alias_method :original_initialize, :initialize unless method_defined?(:original_initialize)
  attr_accessor :only_speedup_battles
  attr_accessor :battle_speed

  def initialize
    original_initialize
    @only_speedup_battles = 0
    @battle_speed = 0
  end
end

#===============================================================================#
# Options menu
#===============================================================================#
MenuHandlers.add(:options_menu, :only_speedup_battles, {
  "name" => _INTL("Speed Up Settings"),
  "order" => 25,
  "type" => EnumOption,
  "parameters" => [_INTL("Always"), _INTL("Only Battles")],
  "description" => _INTL("Choose which aspect is sped up."),
  "get_proc" => proc { next $PokemonSystem.only_speedup_battles },
  "set_proc" => proc { |value, scene|
    $GameSpeed = 0 if value != $PokemonSystem.only_speedup_battles
    $PokemonSystem.only_speedup_battles = value
    $CanToggle = value == 0
  }
})

MenuHandlers.add(:options_menu, :battle_speed, {
  "name" => _INTL("Battle Speed"),
  "order" => 26,
  "type" => EnumOption,
  "parameters" => [_INTL("x#{SPEEDUP_STAGES[0]}"), _INTL("x#{SPEEDUP_STAGES[1]}"), _INTL("x#{SPEEDUP_STAGES[2]}")],
  "description" => _INTL("Choose the battle speed when the battle speed-up is set to 'Battles Only'."),
  "get_proc" => proc { next $PokemonSystem.battle_speed },
  "set_proc" => proc { |value, scene|
    $PokemonSystem.battle_speed = value
  }
})

#===============================================================================#
# Scene_Map HUD
#===============================================================================#
class Scene_Map
  alias delta_speedup_update_scene update unless method_defined?(:delta_speedup_update_scene)

  def update
    delta_speedup_update_scene
    create_speed_hud unless @delta_speed_hud
    update_speed_hud if @delta_speed_hud
  end

  def create_speed_hud
    return unless @spriteset && @spriteset.viewport1
    @delta_speed_hud = BitmapSprite.new(120, 48, @spriteset.viewport1)
    @delta_speed_hud.z = 9999
    update_speed_hud
  end

  def update_speed_hud
    return unless @delta_speed_hud
    @delta_speed_hud.bitmap.clear
    text = "Speed x#{SPEEDUP_STAGES[$GameSpeed]}"
    pbDrawTextPositions(@delta_speed_hud.bitmap, [[text, 0, 0, :left, Color.new(255,255,255), Color.new(0,0,0)]])
  end
end

# --- HUD "Speed x…" en combat (safe hook) ---
class Scene_Battle
  # On n'alias pas si 'update' n'existe pas encore ; on appellera 'super' le cas échéant.
  alias delta_speedup_update_btl update if method_defined?(:update)

  def update
    if defined?(delta_speedup_update_btl)
      delta_speedup_update_btl
    else
      super   # Scene_Base#update existe, donc on a toujours quelque chose à appeler
    end
    create_speed_hud unless @delta_speed_hud
    update_speed_hud if @delta_speed_hud
  end

  def create_speed_hud
    # Choix d'un viewport valide
    vp = (instance_variable_defined?(:@viewport) && @viewport) ||
         (instance_variable_defined?(:@viewport1) && @viewport1)
    return unless vp
    @delta_speed_hud = BitmapSprite.new(120, 48, vp)
    @delta_speed_hud.z = 9999
    update_speed_hud
  end

  def update_speed_hud
    return unless @delta_speed_hud
    @delta_speed_hud.bitmap.clear
    text = "Speed x#{SPEEDUP_STAGES[$GameSpeed]}"
    pbDrawTextPositions(@delta_speed_hud.bitmap,
      [[text, 0, 0, :left, Color.new(255,255,255), Color.new(0,0,0)]]
    )
  end
end


