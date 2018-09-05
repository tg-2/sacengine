import dagon;
import std.math;
import std.stdio;
import std.string;

import sacobject, sxmd;

class TestScene: Scene{
	//OBJAsset aOBJ;
	//Texture txta;
	string[] args;
	this(SceneManager smngr, string[] args){
        super(smngr);
        this.args=args;
    }
    override void onAssetsRequest(){
	    //aOBJ = addOBJAsset("../jman.obj");
	    //txta = New!Texture(null);// TODO: why?
	    //txta.image = loadTXTR("extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/M001.TXTR");
	    //txta.createFromImage(txta.image);
    }
    override void onAllocate(){
        super.onAllocate();

        view = New!Freeview(eventManager, assetManager);
        createSky();
        //auto mat = createMaterial();
        //mat.diffuse = Color4f(0.2, 0.2, 0.2, 0.2);
        //mat.diffuse=txta;

        /+auto obj = createEntity3D();
        obj.drawable = aOBJ.mesh;
        obj.material = mat;
        obj.position = Vector3f(0, 1, 0);
        obj.rotation = rotationQuaternion(Axis.x,-cast(float)PI/2);+/

        foreach(file;args[1..$]){
	        if(file.endsWith(".SXMD")){
		        auto sx=New!SXMDObject(this, file);
		        sx.createEntities(this);
	        }else{
		        auto sac=New!SacObject(this, file);
		        sac.createEntities(this);
	        }
        }

        /+auto ePlane = createEntity3D();
        ePlane.drawable = New!ShapePlane(10, 10, 1, assetManager);
        auto matGround = createMaterial();
        //matGround.diffuse = ;
        ePlane.material=matGround;+/
    }
}

class MyApplication: SceneApplication{
    this(string[] args){
        super(1280, 720, false, "Dagon demo", args);
        TestScene test = New!TestScene(sceneManager, args);
        sceneManager.addScene(test, "TestScene");
        sceneManager.goToScene("TestScene");
    }
}

void main(string[] args){
	if(args.length==1) args~="extracted/jamesmod/JMOD.WAD!/modl.FLDR/jman.MRMC/jman.MRMM";
    MyApplication app = New!MyApplication(args);
    app.run();
    Delete(app);
}
