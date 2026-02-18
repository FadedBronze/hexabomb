package main
import la "core:math/linalg"
import "core:math"
import rl "vendor:raylib"
import "core:math/rand"
import sm "core:container/small_array"

Shot :: struct {
    position: la.Vector2f32,
    velocity: la.Vector2f32,
    last_damaged: HalfGridPosition,
}

EntityType :: enum {
    Nuke,
    Shot,
    MortarShot,
}

SimulationEntity :: struct {
    type: EntityType,
    completed: bool,
    playerIndex: u8,
    halfgridPos: HalfGridPosition,
    damage: u8,
    using shot: Shot,
}

DecayFn :: proc(t: f32) -> f32

ParticleBase :: struct {
    colors: []rl.Color,
    friction: f32,
    initialTimeSeconds: f32,
    summonFrequency: f32,
    size: f32,
    summonQuantity: u32,
    summon: ^ParticleBase,
    sizeDecay: DecayFn,
    colorDecay: DecayFn,
    shape: enum {
        Circle,
        Hexagon,
    },
    speed: f32,
    inheritVelocity: f32,
    sfxPlayTime: f32,
    sfxName: string,
}

Particle :: struct {
    using base: ^ParticleBase,
    followEntityId: u32,
    position: la.Vector2f32,
    velocity: la.Vector2f32,
    timeLeftSeconds: f32,
    timeTillSummon: f32,
    timeTillSfx: f32,
}

explosion_mini := ParticleBase{
    speed = 150,
    friction = 0.01,
    colors = []rl.Color{
        {0, 0, 0, 255},
        {0, 0, 0, 0},
    },
    colorDecay = proc(t: f32) -> f32 { return math.pow(t, 0.5) },
    sizeDecay = constant,
    size = 10,
    initialTimeSeconds = 0.2,
    shape = .Circle,
}

linear := proc(t: f32) -> f32 { return t }
constant := proc(t: f32) -> f32 { return 1 }

explosion_middle := ParticleBase{
    friction = 0.01,
    colors = []rl.Color{
        {255, 255, 255, 255},
        {255, 125, 0, 255},
        {255, 125, 0, 255},
        {255, 0, 0, 255},
        {255, 0, 0, 255},
    },
    colorDecay = linear,
    sizeDecay = constant,
    size = 5,
    initialTimeSeconds = 0.2,
    shape = .Circle,
    summonQuantity = 4,
    summon = &explosion_mini,
    speed = 300,
    summonFrequency = 1 / 0.18,
}

explosion := ParticleBase {
    colors = []rl.Color{
        {255, 255, 255, 255},
        {255, 125, 0, 255},
        {0, 0, 0, 255},
        {0, 0, 0, 0}
    },
    colorDecay = linear,
    sizeDecay = linear,
    size = 50,
    initialTimeSeconds = 0.15,
    shape = .Circle,
    friction = 0,
    summonQuantity = 6,
    summon = &explosion_middle,
    summonFrequency = 1 / 0.13,
    sfxName = "explosion.mp3",
    sfxPlayTime = 0.1,
}

trail_particle := ParticleBase {
    speed = 150,
    inheritVelocity = 0.2,
    colors = []rl.Color{
        {255, 255, 255, 255},
        {255, 125, 0, 255},
        {255, 0, 0, 255},
        {0, 0, 0, 255},
        {0, 0, 0, 0}
    },
    colorDecay = proc(t: f32) -> f32 { return math.pow(t, 1) },
    sizeDecay = proc(t: f32) -> f32 { return 1 - t },
    size = 15,
    initialTimeSeconds = 0.5,
    shape = .Circle,
}

trail_emitter := ParticleBase {
    colors = []rl.Color{
        {0, 0, 0, 0}
    },
    colorDecay = proc(t: f32) -> f32 { return math.pow(t, 1) },
    sizeDecay = proc(t: f32) -> f32 { return t },
    shape = .Circle,
    summonFrequency = 25,
    summonQuantity = 6,
    summon = &trail_particle,
}

blend_two_colors :: proc(b: rl.Color, a: rl.Color, t: f32) -> rl.Color {
    rr := (f32(a.r) - f32(b.r)) * t + f32(b.r)
    gg := (f32(a.g) - f32(b.g)) * t + f32(b.g)
    bb := (f32(a.b) - f32(b.b)) * t + f32(b.b)
    aa := (f32(a.a) - f32(b.a)) * t + f32(b.a)

    return rl.Color{u8(rr), u8(gg), u8(bb), u8(aa)}
}

blend_colors :: proc(colors: []rl.Color, t: f32) -> rl.Color {
    assert(len(colors)>0)

    if len(colors) == 1 {
        return colors[0]
    }

    t := t
    if t == 1 {
        t = 0.999
    }

    curr := t * f32(len(colors)-1)

    colorIdxDown: int = int(curr)
    colorIdxUp: int = int(curr)+1

    t = (curr - f32(colorIdxDown)) / f32(len(colors))

    return blend_two_colors(colors[colorIdxDown], colors[colorIdxUp], t)
}

Simulation :: struct {
    entities: sm.Small_Array(MAX_ENTITIES, SimulationEntity),
    particles: sm.Small_Array(MAX_PARTICLES, Particle),

    completed_entities: u32,
}

simulate_particles :: proc(game: ^Game, dt: f32) -> (completed_particles: bool) {
    completed := 0

    for i in 0..<game.particles.len {
        particle := sm.get_ptr(&game.particles, i)
        following := particle.followEntityId != 0

        particle.timeLeftSeconds -= dt

        if particle.timeLeftSeconds < 0 && !following {
            completed += 1
            continue
        }

        followingEntity := following ? sm.get_ptr(&game.entities, int(particle.followEntityId-1)) : nil
        following_has_completed := following && followingEntity.completed
        
        if following_has_completed {
            completed += 1
            continue
        }

        elapsed := particle.initialTimeSeconds - particle.timeLeftSeconds

        particle.timeTillSfx -= dt

        if particle.sfxPlayTime != 0 && particle.timeTillSfx < 0 {
            particle.timeTillSfx = particle.sfxPlayTime
            play_audio(particle.sfxName)
        }

        if following {
            particle.position = followingEntity.position
        } else {
            particle.position += particle.velocity * dt * math.pow_f32(1+particle.friction, elapsed)
        }

        particle.timeTillSummon -= dt

        if particle.timeTillSummon < 0 {
            if particle.summon != nil {
                particle.timeTillSummon = 1 / particle.summonFrequency

                for _ in 0..<particle.summonQuantity {
                    new_particle := add_particle(game, create_particle(particle.summon))

                    if following {
                        new_particle.velocity += followingEntity.velocity * particle.inheritVelocity
                    } else {
                        new_particle.velocity += particle.velocity * particle.inheritVelocity
                    }

                    new_particle.position = particle.position
                }
            }
        }

        t := elapsed / particle.initialTimeSeconds

        color := blend_colors(
            particle.colors,
            particle.colorDecay(t)
        )

        switch particle.shape {
        case .Hexagon:
            fill_hexagon(
                i32(particle.position.x), 
                i32(particle.position.y), 
                i32(particle.sizeDecay(t)*particle.size), 
                color,
            )
        case .Circle:
            rl.DrawCircle(
                i32(particle.position.x), 
                i32(particle.position.y), 
                particle.sizeDecay(t)*particle.size, 
                color,
            )
        }
    }
    
    i := 0
    for i < game.particles.len {
        particle := sm.get_ptr(&game.particles, i)
        following := particle.followEntityId != 0

        if particle.timeLeftSeconds > 0 || following {
            i += 1
            continue
        }

        sm.unordered_remove(&game.particles, i)
    }

    return game.particles.len == completed
}

simulate_entities :: proc(game: ^Game, dt: f32) {
    size :: 24

    for i in 0..<game.entities.len {
        entity := &game.entities.data[i]

        if entity.completed {
            continue
        }

        switch entity.type {
        case .MortarShot:
            tile := get_tile(&game.tileGrid, entity.halfgridPos)
            damage_tile(game, entity.halfgridPos, entity.damage)

            complete_entity(game, entity)
        case .Nuke:
            damage_tile(game, entity.halfgridPos, entity.damage)

            for dir in directions {
                damage_tile(game, entity.halfgridPos + dir, entity.damage)
            }

            complete_entity(game, entity)
        case .Shot:
            shot := &entity.shot

            prevpos := shot.position

            shot.position += shot.velocity * dt

            halfgridPos := get_tile_grid_pos(&game.tileGrid, shot.position)
            tile := get_tile(&game.tileGrid, halfgridPos)

            screenHalfPos := get_screen_position(&game.tileGrid, halfgridPos)
            
            if !within_halfgrid_range(game.tileGrid.size, halfgridPos) {
                complete_entity(game, entity)
                add_particle(game, &explosion, opts={position=entity.position})
            }

            if shot.last_damaged == halfgridPos {
                break;
            }
            
            if tile.type == .Shield {
                bounce_dir := directions[tile.direction]

                fwd_pos := get_screen_position(&game.tileGrid, halfgridPos + bounce_dir)
                vel := (fwd_pos - screenHalfPos)

                shot.velocity = vel * CANNONBALL_SPEED
                shot.position = get_screen_position(&game.tileGrid, halfgridPos)
            }
            shot.last_damaged = halfgridPos
            
            if tile.playerId != entity.playerIndex+1 {
                damage_tile(game, halfgridPos, entity.damage)
            }
        }
    }

}

simulate :: proc(game: ^Game, dt: f32) {
    simulate_entities(game, dt)
    completed := simulate_particles(game, dt)

    if int(game.completed_entities) == game.entities.len && completed {
        sm.clear(&game.entities)
        sm.clear(&game.particles)
        game.completed_entities = 0
        game.state = .Playing
        crown_winner(game)
        return
    }
}

complete_entity :: proc(game: ^Game, entity: ^SimulationEntity) {
    game.completed_entities += 1
    entity.completed = true

    origin_tile := get_tile(&game.tileGrid, entity.halfgridPos)
    // This wipes all on that tile but none should stay on it anyway
    origin_tile.entityIds = {}
}

damage_tile :: proc(game: ^Game, halfGridPos: HalfGridPosition, amount: u8) {
    tile := get_tile(&game.tileGrid, halfGridPos)

    if tile.type == .Landmine {
        add_particle(game, &explosion, opts={position=halfGridPos})

        for direction in directions {
            for i in 1..<3 {
                damagedTile := get_tile(&game.tileGrid, direction*i16(i) + halfGridPos)
                if tile.playerId != damagedTile.playerId {
                    damage_tile(game, direction*i16(i) + halfGridPos, 2)
                }
            }
        }
    }

    if game.tileTypeStats[tile.type].durability == NA {
        return
    }

    if tile.type != .Free {
        for direction in directions {
            nexttotile := get_tile(&game.tileGrid, halfGridPos + direction)

            if nexttotile.type == .Defense {
                tile = nexttotile
                break
            }
        }
    }

    if amount > tile.durability {
        tile^ = {}
        tile.type = .Free
    } else {
        tile.durability -= amount
    }

    for i in 0..<MAX_PLAYERS {
        if tile.visibility[i] < .Visible {
            tile.visibility[i] = .Visible
        }
    }
}

append_entityId :: proc(tile: ^Tile, entityId: u32) {
    for i in 0..<len(tile.entityIds) {
        id := &tile.entityIds[i]
        if id^ == 0 {
            id^ = entityId
            return
        }
    }
}

AddParticleOpts :: struct {
    position: union {
        HalfGridPosition,
        la.Vector2f32
    }
}

create_particle :: proc(base: ^ParticleBase) -> (p: Particle) {
    p.base = base
    p.timeTillSummon = 1 / base.summonFrequency
    p.timeLeftSeconds = base.initialTimeSeconds

    angle := rand.float32() * math.PI * 2
    vel := base.speed * la.Vector2f32{math.cos(angle), math.sin(angle)}
    p.velocity = vel

    return p
}

add_particle :: proc(game: ^Game, base: ^ParticleBase, opts := AddParticleOpts{}) -> ^Particle {
    particle := create_particle(base)
    
    switch v in opts.position {
        case HalfGridPosition:
            particle.position = get_screen_position(&game.tileGrid, v)
        case la.Vector2f32:
            particle.position = v
    }

    if sm.push(&game.particles, particle) {
        return &game.particles.data[game.particles.len-1]
    }

    return nil
}

add_entity :: proc(game: ^Game, currentPlayerIndex: u8, halfgridPos: HalfGridPosition, entity: SimulationEntity, type: EntityType) -> (entityId: u32) {
    tile := get_tile(&game.tileGrid, halfgridPos)

    append_entityId(tile, u32(game.entities.len)+1)

    sm.append_elem(&game.entities, entity)

    entity := sm.get_ptr(&game.entities, game.entities.len-1)

    entity.playerIndex = currentPlayerIndex
    entity.halfgridPos = halfgridPos
    entity.completed = false
    entity.type = type

    return u32(game.entities.len-1)+1
}

add_cannonball :: proc(game: ^Game, cannonPos: HalfGridPosition, halfgridPos: HalfGridPosition, currentPlayerIdx: u8, dir: HexDirection) {
    pos := get_screen_position(&game.tileGrid, cannonPos)
    fwd_pos := get_screen_position(&game.tileGrid, cannonPos - directions[dir])
    vel := (fwd_pos - pos)

    id := add_entity(game, currentPlayerIdx, halfgridPos, SimulationEntity {
        shot = Shot {
            velocity = vel * CANNONBALL_SPEED,
            position = fwd_pos + (pos - fwd_pos) * 0.25
        },
        damage = game.tileTypeStats[.BlastTarget].damage
    }, EntityType.Shot)

    p := add_particle(game, &trail_emitter, opts={position=halfgridPos})
    p.followEntityId = id
}
