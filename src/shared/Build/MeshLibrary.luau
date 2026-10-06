--!strict
-- The Blender meshes once they've been imported into the place (see tools/meshes): every MeshPart in the
-- imported folder, by name. Builders ask for a mesh here and fall back to plain parts when it isn't there.

local MeshLibrary = {}

local meshes: { [string]: MeshPart } = {}

-- Hands over the folder the meshes were imported into (nil = there isn't one).
function MeshLibrary.set(folder: Instance?)
	local found: { [string]: MeshPart } = {}
	if folder then
		for _, child in folder:GetDescendants() do
			if child:IsA("MeshPart") then
				found[child.Name] = child
			end
		end
	end
	meshes = found
end

function MeshLibrary.get(name: string): MeshPart?
	return meshes[name]
end

-- A fresh copy of a mesh to build with: without anything Studio's importer added to it, and not anchored.
function MeshLibrary.copy(name: string): MeshPart?
	local source = meshes[name]
	if not source then
		return nil
	end
	local copy = source:Clone()
	for _, child in copy:GetChildren() do
		child:Destroy()
	end
	copy.TextureID = ""
	copy.Anchored = false
	copy:SetAttribute("Mesh", name)
	return copy
end

return MeshLibrary
