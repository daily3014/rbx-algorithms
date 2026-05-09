--[=[
	Algorithm: A*

	Return type: AStar object
	Example usage:
		-- You provide the type for the coordinates
		local Heuristic = function(a: vector, b: vector): number
			return vector.magnitude(a - b)
		end
		-- or:
		local Heuristic = function(a: Vector3, b: Vector3): number
			return (a - b).Magnitude
		end

		-- Can only move up or down
		local MyAStar = AStar.new(Heurstic, {
			vector.create(0, 1, 0),
			vector.create(0, -1, 0)
		})

		MyAStar:set("VisitNode", function(Current: vector, Parent: vector): boolean
			-- Don't visit nodes with a Y value of -3 or less
			return Current.y <= -3
		end)

		local Path = MyAStar:Search(vector.create(15, 0, 23), vector.create(15, 13, 23))
--]=]

--!strict
--!optimize 2
--!native

export type Coordinate<T> = T & {
	x: number,
	y: number,
	z: number,
}

export type Heuristic<T> = (T, T) -> number

local AStar = { Heuristics = {} }
AStar.__index = AStar

export type AStar<T> = setmetatable<{
	Heuristic: Heuristic<T>,
	Directions: {T},
	Interrupts: {
		VisitNode: (T, T) -> boolean,
	}
}, typeof(AStar)>

local DefaultInterrupts = {
	VisitNode = function(): boolean
		return false
	end
}

function AStar.new<T>(Heuristic: Heuristic<Coordinate<T>>, Directions: {Coordinate<T>}): AStar<Coordinate<T>>
	return setmetatable({
		Heuristic = Heuristic,
		Directions = Directions,
		Interrupts = table.clone(DefaultInterrupts)
	}, AStar)
end

function AStar.Search<T>(self: AStar<Coordinate<T>>, Start: T, Goal: T)
	error("Not implemented")
	return {}
end

function AStar.set<T>(self: AStar<Coordinate<T>>, InterruptName: string, InterruptFunction: (T, T) -> boolean)
	error("Not implemented")
end

table.freeze(AStar)
return AStar