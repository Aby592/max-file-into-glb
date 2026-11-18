# 3ds Max product exporter for GLB

Drag [AH_ProductToGLB.ms](./AH_ProductToGLB.ms) into a 3ds Max viewport, choose a product scene, and export a product made of one or more meshes as one GLB. The exporter works on temporary copies so the original product keeps its materials and modifiers.

## Prepare the scene

- Use 3ds Max with its glTF material and GLB exporter available. Install a compatible V-Ray version on the export computer for scenes that use V-Ray.
- For automatic selection, put the product meshes under one object or group named `AH_Model`. Keep the studio lights, stage, backdrop, and camera outside that group. The script also recognizes `AH Model`, `AH-Model`, and `AHModel`.
- Check that the product looks correct in Max and that the export computer can read its texture images, including files on shared drives.

## Export

1. Download `AH_ProductToGLB.ms` using GitHub’s **Download raw file** button.
2. Drag the script into a 3ds Max viewport, or choose **Scripting → Run Script**. Save any open work if Max prompts you.
3. Choose the source `.max` file in the browser. If there is no usable product group, the script treats all exportable meshes outside `Studio_Setup` as parts of one model. It asks you to choose the parts if it finds duplicate product roots, no candidates, or a candidate under a name such as `Stage`, `Floor`, or `Backdrop`. For scenes with unrelated geometry, put the intended parts under `AH_Model` to define the export boundary. Canceling stops the export. The script converts the product materials and reports the output path.

For example, `Models/Apples.max` produces `Models/glb/Apples.glb`. If that name is taken, the next export uses `Apples_1.glb`, then `Apples_2.glb`. Import the resulting GLB into Blender and use Material Preview to inspect it.

## Materials and limitations

The script handles common VRayMtl, Standard, Physical, and glTF materials, including Multi/Sub-Object assignments. It uses connected maps for supported channels and can bake 2D texture effects to 2048 × 2048 images. It checks for external image references before publishing the GLB. Blender can open the result without V-Ray.

The export is a static mesh snapshot. V-Ray lighting, view-dependent shading, and two-sided materials with different front and back finishes can look different in Blender. Compare the exported product under similar lighting when checking color, shine, and bump strength.

If export fails, read the first error in the dialog. A missing image path or unsupported product material points to the asset that needs attention. Any missing scene plug-ins appear separately. The GLB reader has been tested with sample data. An end-to-end visual comparison of the example apple scene is still pending.
