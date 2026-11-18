-- Drop into a 3ds Max viewport, then choose a V-Ray product scene.
(
    fn valueOr owner key fallback =
    (
        if isProperty owner key then getProperty owner key else fallback
    )

    fn activeMap mat slot =
    (
        local enabled = valueOr mat ((slot as string) + "_on") true
        if enabled then valueOr mat slot undefined else undefined
    )

    fn scalarOr value fallback =
    (
        if isKindOf value Number then value as float else fallback
    )

    -- Some plug-in versions expose a map through the parameter alias itself.
    fn channelMap mat slot value =
    (
        if not (valueOr mat ((slot as string) + "_on") true) do return undefined
        local tex = valueOr mat slot undefined
        if isKindOf tex TextureMap then tex else if isKindOf value TextureMap then value else undefined
    )

    fn productNameKey name =
    (
        local key = toLower name
        for separator in #(" ", "_", "-") do key = substituteString key separator ""
        key
    )

    fn isProductMesh obj =
    (
        superClassOf obj == GeometryClass and canConvertTo obj Editable_Mesh
    )

    fn productMeshes root result =
    (
        if isProductMesh root do appendIfUnique result root
        for child in root.children do productMeshes child result
    )

    fn findProductMeshes =
    (
        -- Keep the established naming convention as the first choice.
        local roots = for obj in objects where (toLower obj.name) == "ah_model" collect obj
        if roots.count == 0 do
            roots = for obj in objects where (productNameKey obj.name) == "ahmodel" collect obj
        local meshes = #()
        if roots.count == 1 do productMeshes roots[1] meshes
        if meshes.count > 0 do return meshes

        -- A single mesh outside the standard studio rig needs no selection.
        local candidates = #()
        for obj in objects where isProductMesh obj do
        (
            local ancestor = obj
            while ancestor != undefined and (productNameKey ancestor.name) != "studiosetup" do ancestor = ancestor.parent
            if ancestor == undefined do append candidates obj
        )
        if candidates.count == 1 do return candidates

        local chosen = selectByName title:"Choose the product group or its mesh parts (exclude stage and backdrop)" buttonText:"Export product" single:false
        if chosen == undefined do return undefined
        for obj in chosen do productMeshes obj meshes
        if meshes.count == 0 do throw "The selection contains no exportable product meshes."
        meshes
    )

    -- Bake the connected 2D map as a whole, including its color/output nodes.
    -- Direct image maps can retain native resolution and UV placement.
    fn exportMap tex folder role invert:false height:false strength:1.0 =
    (
        if matchPattern (classOf tex as string) pattern:"Missing*" do
            throw ("Unavailable texture plug-in for " + tex.name + ". Open the scene on a machine with its map plug-in installed.")
        local raw = role != #color
        local paths = #()
        if isProperty tex #HDRIMapName do append paths tex.HDRIMapName
        if isKindOf tex Bitmaptexture do append paths tex.filename
        for p in paths do
        (
            local resolved = if p != undefined and p != "" then mapPaths.getFullFilePath p else undefined
            if resolved == undefined or resolved == "" or not doesFileExist resolved do
                throw ("Cannot locate image for " + tex.name + ": " + (p as string))
        )
        if not invert and not height do
        (
            if isKindOf tex Bitmaptexture do
            (
                return (copy tex)
            )
        )
        local path = pathConfig.appendPath folder (((dotNetClass "System.Guid").NewGuid()).ToString() + ".png")
        local side = 2048
        local img = bitmap side side filename:path gamma:(if raw then 1.0 else 2.2)
        local rendered = undefined
        local renderError = undefined
        try (rendered = renderMap tex into:img size:[side,side] filter:true display:false)
        catch (renderError = getCurrentException() as string)
        if renderError != undefined do
        (
            close img
            throw ("Could not evaluate " + tex.name + " (" + (classOf tex as string) + "): " + renderError)
        )
        if rendered == undefined do throw ("Could not render texture: " + tex.name)
        if height then
        (
            -- Sample untouched rows before replacing each height row with normals.
            local row = getPixels img [0,0] side
            local above = row
            for y = 0 to (side-1) do
            (
                local below = if y+1 < side then getPixels img [0,y+1] side else row
                local normals = for x = 1 to side collect
                (
                    local dx = (row[amin side (x+1)].v - row[amax 1 (x-1)].v) / 255.0
                    local dy = (below[x].v - above[x].v) / 255.0
                    local n = normalize [-dx*strength,dy*strength,1.0]
                    color ((n.x+1)*127.5) ((n.y+1)*127.5) ((n.z+1)*127.5)
                )
                setPixels img [0,y] normals
                above = row
                row = below
            )
        )
        else if invert do
        (
            for y = 0 to (side-1) do
            (
                local row = getPixels img [0,y] side
                for x = 1 to side do row[x] = white - row[x]
                setPixels img [0,y] row
            )
        )
        if not (save img) do throw ("Could not save texture: " + tex.name)
        close img
        local result = Bitmaptexture filename:path
        if raw do result.bitmap = openBitmap path gamma:1.0
        local coords = valueOr tex #coords (valueOr tex #UVGen undefined)
        if coords != undefined and isProperty coords #mapChannel and isKindOf coords.mapChannel Integer do result.coords.mapChannel = coords.mapChannel
        result
    )

    -- Flatten one coat in stack order. A constant Mix with identical endpoints
    -- supplies a gray mask without relying on the Mix spinner's display units.
    fn blendCoat under coat weight mask folder =
    (
        if mask == undefined and weight >= 1 do return (copy coat)
        if not (isKindOf under glTFMaterial and isKindOf coat glTFMaterial) do
            throw ("Cannot flatten coat " + coat.name + " over " + under.name + ". Both layers need glTF-compatible PBR channels.")
        local result = copy under
        local gray = white * weight
        local coverage = if mask != undefined then mask else Mix color1:gray color2:gray
        for pair in #(#(#baseColor,#baseColorMap), #(#roughness,#roughnessMap), #(#metalness,#metalnessMap), #(#emissionColor,#emissionMap), #(#normal,#normalMap), #(undefined,#AlphaMap)) do
        (
            local factor = pair[1]
            local slot = pair[2]
            local a = getProperty under slot
            local b = getProperty coat slot
            local va = if factor != undefined then getProperty under factor else white
            local vb = if factor != undefined then getProperty coat factor else white
            if slot == #normalMap do (va = color 128 128 255; vb = va)
            if a == undefined and b == undefined and mask == undefined and factor != undefined and slot != #normalMap then
                setProperty result factor (va * (1-weight) + vb * weight)
            else if a != undefined or b != undefined or va != vb do
            (
                local ca = if isKindOf va Number then white * va else va
                local cb = if isKindOf vb Number then white * vb else vb
                local mixed = Mix color1:ca color2:cb map1:a map2:b mask:coverage
                local role = if slot == #baseColorMap or slot == #emissionMap then #color else #data
                setProperty result slot (exportMap mixed folder role)
                if factor != undefined do setProperty result factor (if isKindOf (getProperty under factor) Number then 1.0 else white)
                if slot == #AlphaMap do result.alphaMode = 3
            )
        )
        result
    )

    fn convertMaterial src folder sources results =
    (
        if src == undefined do return undefined
        local index = findItem sources src
        if index > 0 do return results[index]
        local dst = undefined
        case of
        (
            (isKindOf src MultiMaterial):
            (
                dst = copy src
                for i = 1 to src.materialList.count where src.materialList[i] != undefined do
                    dst.materialList[i] = convertMaterial src.materialList[i] folder sources results
            )
            ((classOf src as string) == "VRayMtl"):
            (
                dst = glTFMaterial name:src.name
                local base = valueOr src #diffuse white
                local diffuseMap = channelMap src #texmap_diffuse base
                if diffuseMap == undefined then (if isKindOf base Color do dst.baseColor = base)
                else dst.baseColorMap = exportMap diffuseMap folder #color
                local roughMode = valueOr src #brdf_useRoughness (valueOr src #option_useRoughness false)
                local gloss = valueOr src #reflection_glossiness 1.0
                local reflectionMap = channelMap src #texmap_reflectionGlossiness gloss
                if reflectionMap == undefined then
                (
                    local g = scalarOr gloss 1.0
                    dst.roughness = if roughMode then g else (1.0 - g)
                )
                else
                (
                    dst.roughness = 1
                    dst.roughnessMap = exportMap reflectionMap folder #data invert:(not roughMode)
                )
                local metalValue = valueOr src #metalness 0.0
                local metal = channelMap src #texmap_metalness metalValue
                if metal == undefined then dst.metalness = scalarOr metalValue 0.0
                else
                (
                    dst.metalness = 1
                    dst.metalnessMap = exportMap metal folder #data
                )
                local bump = activeMap src #texmap_bump
                if bump != undefined do
                (
                    local amount = (scalarOr (valueOr src #texmap_bump_multiplier 100.0) 100.0) / 100.0
                    local normalTex = valueOr bump #normal_map undefined
                    if normalTex == undefined then
                        dst.normalMap = exportMap bump folder #data height:true strength:amount
                    else
                    (
                        dst.normal = amount * (scalarOr (valueOr bump #normal_spin 1.0) 1.0)
                        dst.normalMap = exportMap normalTex folder #data
                    )
                )
                local alpha = activeMap src #texmap_opacity
                if alpha != undefined do
                (
                    dst.alphaMode = 3
                    dst.AlphaMap = exportMap alpha folder #data
                )
                local emission = activeMap src #texmap_self_illumination
                if emission != undefined do
                (
                    dst.emissionColor = white
                    dst.emissionMap = exportMap emission folder #color
                )
            )
            ((classOf src as string) == "VRayOverrideMtl"):
            (
                -- Export the surface visible to the camera. Other slots only
                -- replace this surface for specific V-Ray ray types.
                local visibleMtl = valueOr src #baseMtl undefined
                if visibleMtl == undefined or not (valueOr src #baseMtl_on true) do
                    throw ("Assign and enable a Base material on " + src.name + " (VRayOverrideMtl), then export again.")
                dst = copy (convertMaterial visibleMtl folder sources results)
                dst.name = src.name
            )
            ((classOf src as string) == "VRayBlendMtl"):
            (
                local baseLayer = getSubMtl src 1
                if baseLayer != undefined then dst = copy (convertMaterial baseLayer folder sources results)
                else
                (
                    dst = glTFMaterial()
                    dst.alphaMode = 3
                    dst.AlphaMap = exportMap (Mix color1:black color2:black) folder #data
                )
                local amounts = valueOr src #texmap_blend_multiplier (valueOr src #texmap_blend_mult undefined)
                local switches = valueOr src #coatMtl_on undefined
                for i = 1 to src.coatMtl.count where src.coatMtl[i] != undefined do
                (
                    if switches == undefined or switches[i] do
                    (
                        local tint = src.blend[i]
                        local weight = (tint.r + tint.g + tint.b) / 765.0
                        local mask = src.texmap_blend[i]
                        if mask != undefined and amounts != undefined do
                        (
                            local fraction = (amax 0.0 (amin 100.0 amounts[i])) / 100.0
                            if fraction == 0 then mask = undefined
                            else if fraction < 1 do
                            (
                                local g = white * weight
                                local m = white * fraction
                                mask = Mix color1:g map2:mask mask:(Mix color1:m color2:m)
                            )
                        )
                        if mask != undefined or weight > 0 do
                        (
                            local coat = convertMaterial src.coatMtl[i] folder sources results
                            dst = blendCoat dst coat weight mask folder
                        )
                    )
                )
                dst.name = src.name
            )
            ((classOf src as string) == "VRay2SidedMtl"):
            (
                if src.frontMtl == undefined do throw ("Missing front material: " + src.name)
                dst = copy (convertMaterial src.frontMtl folder sources results)
                dst.name = src.name
                if isProperty dst #doubleSided do dst.doubleSided = true
            )
            (isKindOf src StandardMaterial):
            (
                dst = glTFMaterial name:src.name
                local tex = if src.diffuseMapEnable then src.diffuseMap else undefined
                if tex == undefined then dst.baseColor = src.diffuse
                else dst.baseColorMap = exportMap tex folder #color
                dst.roughness = 1.0 - (scalarOr src.glossiness 0.0) / 100.0
                if src.glossinessMapEnable and src.glossinessMap != undefined do
                (
                    dst.roughness = 1
                    dst.roughnessMap = exportMap src.glossinessMap folder #data invert:true
                )
                if src.bumpMapEnable and src.bumpMap != undefined do
                    dst.normalMap = exportMap src.bumpMap folder #data height:true strength:(src.bumpMapAmount / 100.0)
                if src.opacityMapEnable and src.opacityMap != undefined do
                (
                    dst.alphaMode = 3
                    dst.AlphaMap = exportMap src.opacityMap folder #data
                )
            )
            (isKindOf src glTFMaterial or isKindOf src PhysicalMaterial):
            (
                dst = copy src
                -- The native exporter needs Bitmaptexture inputs even when the
                -- owning material itself is already an exportable material.
                for i = 1 to getNumSubTexmaps dst do
                (
                    local tex = getSubTexmap dst i
                    if tex != undefined and not (isKindOf tex Bitmaptexture) do
                    (
                        local label = toLower (getSubTexmapSlotName dst i)
                        local isColor = matchPattern label pattern:"*color*" or matchPattern label pattern:"*emission*"
                        setSubTexmap dst i (exportMap tex folder (if isColor then #color else #data))
                    )
                )
            )
            default: throw ("Unsupported material: " + src.name + " (" + (classOf src as string) + ")")
        )
        append sources src
        append results dst
        dst
    )

    fn checkGLB path convertedMaterials =
    (
        local stream = (dotNetClass "System.IO.File").OpenRead path
        local reader = dotNetObject "System.IO.BinaryReader" stream
        local problem = undefined
        try
        (
            if reader.ReadUInt32() != 0x46546C67 or reader.ReadUInt32() != 2 do throw "Invalid GLB header."
            if reader.ReadUInt32() != stream.Length do throw "Incomplete GLB file."
            local count = reader.ReadInt32()
            if reader.ReadUInt32() != 0x4E4F534A do throw "Missing GLB scene data."
            local bytes = reader.ReadBytes count
            -- Max may start before the .NET serialization assemblies are loaded.
            -- Framework and newer .NET hosts put these types in different assemblies.
            local factory = undefined
            local quotaType = undefined
            for assemblyName in #("System.Runtime.Serialization", "System.Private.DataContractSerialization") while (factory == undefined or quotaType == undefined) do
            (
                dotNet.loadAssembly assemblyName returnPassFail:true
                factory = dotNetClass "System.Runtime.Serialization.Json.JsonReaderWriterFactory"
                quotaType = dotNetClass "System.Xml.XmlDictionaryReaderQuotas"
            )
            if factory == undefined or quotaType == undefined do
                throw "GLB validation could not start. The .NET JSON reader is unavailable in this 3ds Max installation."
            dotNet.loadAssembly "System.Xml" returnPassFail:true
            local jsonReader = factory.CreateJsonReader bytes quotaType.Max
            local doc = dotNetObject "System.Xml.XmlDocument"
            doc.Load jsonReader
            jsonReader.Close()
            if (doc.SelectNodes "/root/buffers/item/uri[not(starts-with(.,'data:'))] | /root/images/item/uri[not(starts-with(.,'data:'))]").Count > 0 do
                throw "The exporter left an external resource reference in the GLB."
            local images = doc.SelectNodes "/root/images/item"
            for i = 0 to (images.Count-1) do
            (
                local img = images.ItemOf[i]
                if (img.SelectSingleNode "bufferView | uri") == undefined do throw "A GLB image has no embedded data."
            )
            local emitted = doc.SelectNodes "/root/materials/item"
            if emitted.Count == 0 and convertedMaterials.count > 0 do throw "The exporter omitted all product materials."
            for i = 0 to (emitted.Count-1) do
            (
                local entry = emitted.ItemOf[i]
                local nameNode = entry.SelectSingleNode "name"
                if nameNode != undefined do
                    for mat in convertedMaterials where isKindOf mat glTFMaterial and mat.name == nameNode.InnerText do
                    (
                        for pair in #(#(#baseColorMap,"pbrMetallicRoughness/baseColorTexture"), #(#normalMap,"normalTexture"), #(#roughnessMap,"pbrMetallicRoughness/metallicRoughnessTexture"), #(#metalnessMap,"pbrMetallicRoughness/metallicRoughnessTexture"), #(#emissionMap,"emissiveTexture")) do
                        (
                            if (getProperty mat pair[1]) != undefined and (entry.SelectSingleNode pair[2]) == undefined do
                                throw ("The exporter omitted " + (pair[1] as string) + " on " + mat.name)
                        )
                    )
            )
        )
        catch (problem = getCurrentException())
        reader.Close()
        if problem != undefined do throw (problem as string)
    )

    fn exportProduct modelPath missingPlugins =
    (
        if not doesFileExist modelPath do throw ("File cannot be found: " + modelPath)
        if not isMaxFile modelPath do throw ("3ds Max cannot read this file as a MAX scene: " + modelPath)
        if not checkForSave() do return undefined
        local reported = #()
        local detail = ""
        local loaded = try (loadMaxFile modelPath useFileUnits:true quiet:true missingDLLsAction:#logmsg missingDLLsList:&reported)
                       catch (detail = "\n" + (getCurrentException() as string); false)
        if reported != undefined do
            for entry in reported do
            (
                append missingPlugins (entry as string)
                format "Scene references missing plug-in: %\n" entry
            )
        if not loaded do throw ("3ds Max could not open:\n" + modelPath + detail + "\nOpen it with File > Open to see Max's loading messages.")
        local meshes = findProductMeshes()
        if meshes == undefined do return undefined
        local duplicates = #()
        local oldSelection = selection as array
        local sources = #()
        local materials = #()
        local outputDir = pathConfig.appendPath (getFilenamePath modelPath) "glb"
        local fs = dotNetClass "System.IO.File"
        local dir = dotNetClass "System.IO.Directory"
        local tempDir = pathConfig.appendPath outputDir (((dotNetClass "System.Guid").NewGuid()).ToString())
        local failure = undefined
        local finalPath = undefined
        try
        (
            dir.CreateDirectory tempDir
            with animate off with undo off
            (
                for obj in meshes do
                (
                    local duplicate = snapshot obj
                    append duplicates duplicate
                    local materialError = undefined
                    try (duplicate.material = convertMaterial obj.material tempDir sources materials)
                    catch (materialError = getCurrentException() as string)
                    if materialError != undefined do
                        throw ("Product object " + obj.name + ", material " + (obj.material as string) + ":\n" + materialError)
                )
                select duplicates
                local staged = pathConfig.appendPath tempDir "product.glb"
                if (exportFile staged #noPrompt selectedOnly:true using:GLTF_Export) == false or not (fs.Exists staged) do
                    throw "3ds Max could not export the product."
                checkGLB staged materials
                local base = pathConfig.appendPath outputDir (getFilenameFile modelPath)
                finalPath = base + ".glb"
                local suffix = 1
                while fs.Exists finalPath do
                (
                    finalPath = base + "_" + (suffix as string) + ".glb"
                    suffix += 1
                )
                fs.Move staged finalPath
            )
        )
        catch (failure = getCurrentException())
        with undo off (for obj in duplicates where isValidNode obj do delete obj)
        if oldSelection.count == 0 then clearSelection() else select oldSelection
        freeSceneBitmaps()
        try (if dir.Exists tempDir do dir.Delete tempDir true) catch (format "Temporary export files: %\n" tempDir)
        if failure != undefined do throw (failure as string)
        finalPath
    )

    local inputFile = getOpenFileName caption:"Choose product scene" types:"3ds Max scene (*.max)|*.max|"
    if inputFile != undefined do
    (
        local missingPlugins = #()
        try
        (
            local result = exportProduct inputFile missingPlugins
            if result != undefined do messageBox result title:"GLB exported"
        )
        catch
        (
            local reason = getCurrentException() as string
            if missingPlugins.count > 0 do
            (
                reason += "\n\nMissing plug-ins reported by 3ds Max:"
                for entry in missingPlugins do reason += "\n" + entry
            )
            messageBox reason title:"GLB export failed"
        )
    )
)
