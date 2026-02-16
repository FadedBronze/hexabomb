package main
import la "core:math/linalg"
import "core:math"
import rl "vendor:raylib"
import "core:math/rand"
import sm "core:container/small_array"

Shot :: struct {
    position: la.Vector2f32,
    velocity: la.Vector2f32,
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

Particle :: struct {
    position: la.Vector2f32,
    velocity: la.Vector2f32,
    colors: []rl.Color,
    friction: f32,
    timeLeftSeconds: f32,
    initialTimeSeconds: f32,
    timeTillSummon: f32,
    summonFrequency: f32,
    size: f32,
    summonQuantity: u32,
    summon: ^Particle,
    sizeDecay: DecayFn,
    colorDecay: DecayFn,
    shape: enum {
        Circle,
        Hexagon,
    },
}

explosion := Particle {
    position = {0, 0},
    velocity = {0, 0},
    colors = []rl.Color{
        {0, 0, 0, 255},
        {255, 255, 255, 255},
        {255, 125, 0, 255},
    },
    colorDecay = proc(t: f32) -> f32 { return math.pow_f32(t, 20) },
    sizeDecay = proc(t: f32) -> f32 { return math.sin_f32(t*51) },
    size = 25,
    timeLeftSeconds = 1.0,
    initialTimeSeconds = 1.0,
    timeTillSummon = 0.9,
    summonFrequency = 1,
    shape = .Hexagon,
    friction = 0,
    summonQuantity = 8,
    summon = &Particle {
        friction = 0.2,
        position = {0, 0},
        velocity = {200, 200},
        colors = []rl.Color{
            {255, 255, 255, 255},
            {255, 125, 0, 255},
            {255, 125, 0, 255},
            {255, 0, 0, 255},
            {255, 0, 0, 255},
        },
        colorDecay = proc(t: f32) -> f32 { return t },
        sizeDecay = proc(t: f32) -> f32 { return math.sin_f32(t*89)/8 + 7/8 },
        size = 45,
        timeLeftSeconds = 0.2,
        initialTimeSeconds = 0.2,
        shape = .Circle,
    }
}

blend_two_colors :: proc(a: rl.Color, b: rl.Color, t: f32) -> rl.Color {
    rr := f32(a.r - b.r) * t + f32(b.r)
    gg := f32(a.g - b.g) * t + f32(b.g)
    bb := f32(a.b - b.b) * t + f32(b.b)
    aa := f32(a.a - b.a) * t + f32(b.a)

    return rl.Color{u8(rr), u8(gg), u8(bb), u8(aa)}
}

blend_colors :: proc(colors: []rl.Color, t: f32) -> rl.Color {
    curr := t * f32(len(colors)-1)

    colorIdxDown: int = int(curr)
    colorIdxUp: int = int(curr+1)

    t := (curr - f32(colorIdxDown)) / f32(len(colors))

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

        elapsed := particle.initialTimeSeconds - particle.timeLeftSeconds

        particle.position += particle.velocity * dt * math.pow_f32(particle.friction, elapsed)
        
        particle.timeLeftSeconds -= dt

        if particle.timeLeftSeconds < 0 {
            completed += 1
            continue
        }

        particle.timeTillSummon -= dt

        if particle.timeTillSummon < 0 {
            if particle.summon != nil {
                particle.timeTillSummon = 1 / particle.summonFrequency

                for _ in 0..<particle.summonQuantity {
                    new_particle := particle.summon^

                    angle := rand.float32() * math.PI * 2
                    vel := la.vector_length(new_particle.velocity) * la.Vector2f32{math.cos(angle), math.sin(angle)}
                    new_particle.velocity = vel

                    new_particle.position = particle.position

                    sm.append_elem(&game.particles, new_particle)
                }
            }
        }

        t := particle.timeLeftSeconds / particle.initialTimeSeconds

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

            prevgridpos := get_tile_grid_pos(&game.tileGrid, prevpos)

            prev_tile := get_tile(&game.tileGrid, prevgridpos)

            if prev_tile != tile && prev_tile.playerId - 1 != entity.playerIndex {
                damage_tile(game, prevgridpos, entity.damage)
            }

            if tile.type == .Shield {
                bounce_dir := directions[tile.direction]

                fwd_pos := get_screen_position(&game.tileGrid, halfgridPos + bounce_dir)
                vel := (fwd_pos - screenHalfPos)

                shot.velocity = vel * CANNONBALL_SPEED
            }

            if !within_halfgrid_range(game.tileGrid.size, halfgridPos) {
                complete_entity(game, entity)
            }

            rl.DrawCircle(i32(shot.position.x), i32(shot.position.y), size, rl.BLACK)
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

    for direction in directions {
        nexttotile := get_tile(&game.tileGrid, halfGridPos + direction)

        if nexttotile.type == .Defense {
            tile = nexttotile
            break
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

add_particle :: proc(game: ^Game, halfgridPos: HalfGridPosition, particle: Particle) {
    particle := particle
    particle.position = get_screen_position(&game.tileGrid, halfgridPos)

    sm.push(&game.particles, particle)
}

add_entity :: proc(game: ^Game, currentPlayerIndex: u8, halfgridPos: HalfGridPosition, entity: SimulationEntity, type: EntityType) {
    tile := get_tile(&game.tileGrid, halfgridPos)

    append_entityId(tile, u32(game.entities.len)+1)

    sm.append_elem(&game.entities, entity)

    entity := sm.get_ptr(&game.entities, game.entities.len-1)

    entity.playerIndex = currentPlayerIndex
    entity.halfgridPos = halfgridPos
    entity.completed = false
    entity.type = type
}
