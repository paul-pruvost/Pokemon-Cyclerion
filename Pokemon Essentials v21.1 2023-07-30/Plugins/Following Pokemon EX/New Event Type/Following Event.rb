#-------------------------------------------------------------------------------
# Defining a new method for base Essentials followers to show dust animation
#-------------------------------------------------------------------------------
class Game_Follower
  def update_move
    was_jumping = jumping?
    super
    show_dust_animation if was_jumping && !jumping?
  end

  if !method_defined?(:show_dust_animation)
    def show_dust_animation
      spriteset = $scene.spriteset(map_id)
      spriteset&.addUserAnimation(Settings::DUST_ANIMATION_ID, self.x, self.y, true, 1)
    end
  end
end

#-------------------------------------------------------------------------------
# Defining a new class for Following Pokemon event which has several additions
# to make it more robust as a Following Pokemon
#-------------------------------------------------------------------------------
class Game_FollowingPkmn < Game_Follower
  def initialize(*args)
    super(*args)
  end

  #-----------------------------------------------------------------------------
  # Update pattern at a constant rate independent of move speed
  #-----------------------------------------------------------------------------
  def update_pattern
    return if @lock_pattern
    if @moved_last_frame && !@moved_this_frame && !@step_anime
      @pattern = @original_pattern
      @anime_count = 0
      return
    end
    if !@moved_last_frame && @moved_this_frame && !@step_anime
      @pattern = (@pattern + 1) % 4 if @walk_anime
      @anime_count = 0
      return
    end
    pattern_time = pattern_update_speed / 4   # 4 frames per cycle in a charset
    return if @anime_count < pattern_time
    # Advance to the next animation frame
    @pattern = (@pattern + 1) % 4
    @anime_count -= pattern_time
  end
  #-----------------------------------------------------------------------------
  # Don't turn off walk animation when sliding on ice if the following pokemon
  # is airborne.
  #-----------------------------------------------------------------------------
  alias __followingpkmn__walk_anime walk_anime= unless method_defined?(:__followingpkmn__walk_anime)
  def walk_anime=(value)
    return if $PokemonGlobal.ice_sliding && (!FollowingPkmn.active? || FollowingPkmn.airborne_follower?)
    __followingpkmn__walk_anime(value)
  end
  #-----------------------------------------------------------------------------
  # Don't reset walk animation when sliding on ice if the following pokemon is
  # airborne.
  #-----------------------------------------------------------------------------
  alias __followingpkmn__straighten straighten unless method_defined?(:__followingpkmn__straighten)
  def straighten
    return if $PokemonGlobal.ice_sliding && (!FollowingPkmn.active? || FollowingPkmn.airborne_follower?)
    __followingpkmn__straighten
  end
  #-----------------------------------------------------------------------------
  # Don't show dust animation if Following Pokemon isn't active or is airborne
  #-----------------------------------------------------------------------------
  def show_dust_animation
    return if !FollowingPkmn.active? || FollowingPkmn.airborne_follower?
    super
  end

  #-----------------------------------------------------------------------------
  # Allow following pokemon to freely walk on water
  #-----------------------------------------------------------------------------
  def location_passable?(x, y, direction)
    this_map = self.map
    return false if !this_map || !this_map.valid?(x, y)
    return true if @through
    passed_tile_checks = false
    bit = (1 << ((direction / 2) - 1)) & 0x0f
    # Check all events for ones using tiles as graphics, and see if they're passable
    this_map.events.each_value do |event|
      next if event.tile_id < 0 || event.through || !event.at_coordinate?(x, y)
      tile_data = GameData::TerrainTag.try_get(this_map.terrain_tags[event.tile_id])
      next if tile_data.ignore_passability
      next if tile_data.bridge && $PokemonGlobal.bridge == 0
      return false if tile_data.ledge
      # Allow Folllowers to surf if they can travel on water
      return true if tile_data.can_surf && FollowingPkmn.waterborne_follower?
      passage = this_map.passages[event.tile_id] || 0
      return false if passage & bit != 0
      passed_tile_checks = true if (tile_data.bridge && $PokemonGlobal.bridge > 0) ||
                                   (this_map.priorities[event.tile_id] || -1) == 0
      break if passed_tile_checks
    end
    # Check if tiles at (x, y) allow passage for follower
    if !passed_tile_checks
      [2, 1, 0].each do |i|
        tile_id = this_map.data[x, y, i] || 0
        next if tile_id == 0
        tile_data = GameData::TerrainTag.try_get(this_map.terrain_tags[tile_id])
        next if tile_data.ignore_passability
        next if tile_data.bridge && $PokemonGlobal.bridge == 0
        return false if tile_data.ledge
        # Allow Folllowers to surf if they can travel on water
        return true if tile_data.can_surf && FollowingPkmn.waterborne_follower?
        passage = this_map.passages[tile_id] || 0
        return false if passage & bit != 0
        break if tile_data.bridge && $PokemonGlobal.bridge > 0
        break if (this_map.priorities[tile_id] || -1) == 0
      end
    end
    # Check all events on the map to see if any are in the way
    this_map.events.values.each do |event|
      next if !event.at_coordinate?(x, y)
      return false if !event.through && event.character_name != ""
    end
    return true
  end

  #-----------------------------------------------------------------------------
  # Standard move_fancy method from Game_Follower
  #-----------------------------------------------------------------------------
  def move_fancy(direction)
    delta_x = (direction == 6) ? 1 : (direction == 4) ? -1 : 0
    delta_y = (direction == 2) ? 1 : (direction == 8) ? -1 : 0
    new_x = self.x + delta_x
    new_y = self.y + delta_y
    # Move if new position is the player's, or the new position is passable,
    # or self's current position is not passable
    if ($game_player.x == new_x && $game_player.y == new_y) ||
       location_passable?(new_x, new_y, 10 - direction) ||
       !location_passable?(self.x, self.y, direction)
      move_through(direction)
    end
  end

  #-----------------------------------------------------------------------------
  # Standard jump_fancy method from Game_Follower
  #-----------------------------------------------------------------------------
  def jump_fancy(direction, leader)
    delta_x = (direction == 6) ? 2 : (direction == 4) ? -2 : 0
    delta_y = (direction == 2) ? 2 : (direction == 8) ? -2 : 0
    half_delta_x = delta_x / 2
    half_delta_y = delta_y / 2
    if location_passable?(self.x + half_delta_x, self.y + half_delta_y, 10 - direction)
      # Can walk over the middle tile normally; just take two steps
      move_fancy(direction)
      move_fancy(direction)
    elsif location_passable?(self.x + delta_x, self.y + delta_y, 10 - direction)
      # Can't walk over the middle tile, but can walk over the end tile; jump over
      if location_passable?(self.x, self.y, direction)
        if leader.jumping?
          self.jump_speed = leader.jump_speed || 3
        else
          self.jump_speed = leader.move_speed || 3
          # This is halved because self has to jump 2 tiles in the time it takes
          # the leader to move one tile
          @jump_time /= 2
        end
        jump(delta_x, delta_y)
      else
        # self's current tile isn't passable; just take two steps ignoring passability
        move_through(direction)
        move_through(direction)
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Improved movement method with better synchronization and timing
  #-----------------------------------------------------------------------------
  def fancy_moveto(new_x, new_y, leader)
    if self.x - new_x == 1 && self.y == new_y
      move_fancy(4)
    elsif self.x - new_x == -1 && self.y == new_y
      move_fancy(6)
    elsif self.x == new_x && self.y - new_y == 1
      move_fancy(8)
    elsif self.x == new_x && self.y - new_y == -1
      move_fancy(2)
    elsif self.x - new_x == 2 && self.y == new_y
      jump_fancy(4, leader)
    elsif self.x - new_x == -2 && self.y == new_y
      jump_fancy(6, leader)
    elsif self.x == new_x && self.y - new_y == 2
      jump_fancy(8, leader)
    elsif self.x == new_x && self.y - new_y == -2
      jump_fancy(2, leader)
    elsif self.x != new_x || self.y != new_y
      moveto(new_x, new_y)
    end
  end

  #-----------------------------------------------------------------------------
  # Updating the event turning to prevent following Pokemon from changing its
  # direction with the player
  #-----------------------------------------------------------------------------
  def turn_towards_leader(leader)
    return if FollowingPkmn.active? && !FollowingPkmn::ALWAYS_FACE_PLAYER
    pbTurnTowardEvent(self, leader)
  end

  #-----------------------------------------------------------------------------
  # Simplified follow_leader method based on standard follower logic
  #-----------------------------------------------------------------------------
  def follow_leader(leader, instant = false, leaderIsTrueLeader = true)
    return if @move_route_forcing
    
    # Don't follow if still jumping or moving (let current animation finish)
    return if jumping? || moving?
    
    # End any current movement to prevent conflicts
    end_movement
    
    maps_connected = $map_factory.areConnected?(leader.map.map_id, self.map.map_id)
    target = nil
    
    # Get the target tile that self wants to move to
    if maps_connected
      behind_direction = 10 - leader.direction
      target = $map_factory.getFacingTile(behind_direction, leader)
      if target && $map_factory.getTerrainTag(target[0], target[1], target[2]).ledge
        # Get the tile above the ledge (where the leader jumped from)
        target = $map_factory.getFacingTileFromPos(target[0], target[1], target[2], behind_direction)
      end
      target = [leader.map.map_id, leader.x, leader.y] if !target
    else
      # Map transfer to an unconnected map
      target = [leader.map.map_id, leader.x, leader.y]
    end
    
    # Move self to the target
    if self.map.map_id != target[0]
      vector = $map_factory.getRelativePos(target[0], 0, 0, self.map.map_id, @x, @y)
      @map = $map_factory.getMap(target[0])
      # NOTE: Can't use moveto because vector is outside the boundaries of the
      #       map, and moveto doesn't allow setting invalid coordinates.
      @x = vector[0]
      @y = vector[1]
      @real_x = @x * Game_Map::REAL_RES_X
      @real_y = @y * Game_Map::REAL_RES_Y
    end
    
    if instant || !maps_connected
      moveto(target[1], target[2])
    else
      fancy_moveto(target[1], target[2], leader)
    end
  end

  #-----------------------------------------------------------------------------
  # Make Follower Appear above player
  #-----------------------------------------------------------------------------
  def screen_z(height = 0)
    ret = super
    return ret + 1
  end
  #-----------------------------------------------------------------------------
end

class FollowerData
  #-----------------------------------------------------------------------------
  # Shorthand for checking whether the data is for a Following Pokemon event
  #-----------------------------------------------------------------------------
  def following_pkmn?; return name[/FollowingPkmn/]; end
  #-----------------------------------------------------------------------------
  # Updating the FollowerData interact method to allow Following Pokemon to
  # interact with the player without needing a common event
  #-----------------------------------------------------------------------------
  alias __followingpkmn__interact interact unless method_defined?(:__followingpkmn__interact)
  def interact(*args)
    return __followingpkmn__interact(*args) if !following_pkmn?
    if !@common_event_id
      event = args[0]
      $game_map.refresh if $game_map.need_refresh
      event.lock
      FollowingPkmn.talk
      event.unlock
    elsif FollowingPkmn.can_talk?
      return __followingpkmn__interact(*args)
    end
  end
  #-----------------------------------------------------------------------------
end


class Game_FollowerFactory
  #-----------------------------------------------------------------------------
  # Define the Following as a different class from Game_Follower ie
  # Game_FollowingPkmn
  #-----------------------------------------------------------------------------
  alias __followingpkmn__create_follower_object create_follower_object unless private_method_defined?(:__followingpkmn__create_follower_object)
  def create_follower_object(*args)
    return Game_FollowingPkmn.new(args[0]) if args[0].following_pkmn?
    return __followingpkmn__create_follower_object(*args)
  end
  #-----------------------------------------------------------------------------
  # Following Pokemon shouldn't be a leader if it is inactive.
  #-----------------------------------------------------------------------------
  def move_followers
    leader = $game_player
    $PokemonGlobal.followers.each_with_index do |follower, i|
      event = @events[i]
      event.follow_leader(leader, false, (i == 0))
      follower.x              = event.x
      follower.y              = event.y
      follower.current_map_id = event.map.map_id
      follower.direction      = event.direction
      leader = event if !event.is_a?(Game_FollowingPkmn) || FollowingPkmn.active?
    end
  end
  #-----------------------------------------------------------------------------
  # Following Pokemon shouldn't be a leader if it is inactive.
  #-----------------------------------------------------------------------------
  def turn_followers
    leader = $game_player
    $PokemonGlobal.followers.each_with_index do |follower, i|
      event = @events[i]
      event.turn_towards_leader(leader)
      follower.direction = event.direction
      leader = event if !event.is_a?(Game_FollowingPkmn) || FollowingPkmn.active?
    end
  end
  #-----------------------------------------------------------------------------
  # Method to remove all Followers except Following Pokemon
  #-----------------------------------------------------------------------------
  def remove_all_except_following_pkmn
    followers = $PokemonGlobal.followers
    followers.each_with_index do |follower, i|
      next if follower.following_pkmn?
      followers[i] = nil
      @events[i] = nil
      @last_update += 1
    end
    followers.compact!
    @events.compact!
  end
  #-----------------------------------------------------------------------------
end

#-------------------------------------------------------------------------------
# Improved follower movement with better timing
#-------------------------------------------------------------------------------
class Scene_Map
  alias __followingpkmn__update update unless method_defined?(:__followingpkmn__update)
  def update(*args)
    super(*args)
    # Only move followers when player is moving and followers are ready
    if $game_player.moving?
      $game_temp.followers.move_followers
      $game_temp.followers.turn_followers
    end
  end
end

  #-----------------------------------------------------------------------------
  # Move through obstacles when necessary
  #-----------------------------------------------------------------------------
  def move_through(direction)
    old_through = @through
    @through = true
    
    case direction
    when 2 then move_down
    when 4 then move_left
    when 6 then move_right
    when 8 then move_up
    end
    
    @through = old_through
    @step_anime = true
  end

  #-----------------------------------------------------------------------------
  # Standard location_passable? method from Game_Follower
  #-----------------------------------------------------------------------------
  private

  def location_passable?(x, y, direction)
    this_map = self.map
    return false if !this_map || !this_map.valid?(x, y)
    return true if @through
    passed_tile_checks = false
    bit = (1 << ((direction / 2) - 1)) & 0x0f
    # Check all events for ones using tiles as graphics, and see if they're passable
    this_map.events.each_value do |event|
      next if event.tile_id < 0 || event.through || !event.at_coordinate?(x, y)
      tile_data = GameData::TerrainTag.try_get(this_map.terrain_tags[event.tile_id])
      next if tile_data.ignore_passability
      next if tile_data.bridge && $PokemonGlobal.bridge == 0
      return false if tile_data.ledge
      passage = this_map.passages[event.tile_id] || 0
      return false if passage & bit != 0
      passed_tile_checks = true if (tile_data.bridge && $PokemonGlobal.bridge > 0) ||
                                   (this_map.priorities[event.tile_id] || -1) == 0
      break if passed_tile_checks
    end
    # Check if tiles at (x, y) allow passage for follower
    if !passed_tile_checks
      [2, 1, 0].each do |i|
        tile_id = this_map.data[x, y, i] || 0
        next if tile_id == 0
        tile_data = GameData::TerrainTag.try_get(this_map.terrain_tags[tile_id])
        next if tile_data.ignore_passability
        next if tile_data.bridge && $PokemonGlobal.bridge == 0
        return false if tile_data.ledge
        passage = this_map.passages[tile_id] || 0
        return false if passage & bit != 0
        break if tile_data.bridge && $PokemonGlobal.bridge > 0
        break if (this_map.priorities[tile_id] || -1) == 0
      end
    end
    # Check all events on the map to see if any are in the way
    this_map.events.each_value do |event|
      next if !event.at_coordinate?(x, y)
      return false if !event.through && event.character_name != ""
    end
    return true
  end