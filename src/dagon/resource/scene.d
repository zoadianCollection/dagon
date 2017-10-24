/*
Copyright (c) 2017 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.resource.scene;

import std.stdio;

import dlib.core.memory;

import dlib.container.array;
import dlib.container.dict;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.image.color;

import derelict.opengl.gl;

import dagon.core.ownership;
import dagon.core.event;
import dagon.core.application;
import dagon.resource.asset;
import dagon.resource.textasset;
import dagon.resource.textureasset;
import dagon.resource.fontasset;
import dagon.graphics.environment;
import dagon.graphics.rc;
import dagon.graphics.view;
import dagon.graphics.shapes;
import dagon.graphics.clustered;
import dagon.graphics.shadow;
import dagon.graphics.materials.generic;
import dagon.graphics.materials.bpclustered;
import dagon.graphics.materials.hud;
import dagon.logics.entity;

class Scene: EventListener
{
    SceneManager sceneManager;
    AssetManager assetManager;
    bool canRun = false;
    bool releaseAtNextStep = false;
    bool needToLoad = true;

    this(SceneManager smngr)
    {
        super(smngr.eventManager, null);
        sceneManager = smngr;
        assetManager = New!AssetManager();
    }

    ~this()
    {
        release();
        Delete(assetManager);
    }

    // Set preload to true if you want to load the asset immediately
    // before actual loading (e.g., to render a loading screen)

    Asset addAsset(Asset asset, string filename, bool preload = false)
    {
        if (preload)
            assetManager.preloadAsset(asset, filename);
        else
            assetManager.addAsset(asset, filename);
        return asset;
    }

    TextAsset addTextAsset(string filename, bool preload = false)
    {
        TextAsset text;
        if (assetManager.assetExists(filename))
            text = cast(TextAsset)assetManager.getAsset(filename);
        else
        {
            text = New!TextAsset(assetManager);
            addAsset(text, filename, preload);
        }
        return text;
    }

    TextureAsset addTextureAsset(string filename, bool preload = false)
    {
        TextureAsset tex;
        if (assetManager.assetExists(filename))
            tex = cast(TextureAsset)assetManager.getAsset(filename);
        else
        {
            tex = New!TextureAsset(assetManager.imageFactory, assetManager);
            addAsset(tex, filename, preload);
        }
        return tex;
    }

    FontAsset addFontAsset(string filename, uint height, bool preload = false)
    {
        FontAsset font;
        if (assetManager.assetExists(filename))
            font = cast(FontAsset)assetManager.getAsset(filename);
        else
        {
            font = New!FontAsset(height, assetManager);
            addAsset(font, filename, preload);
        }
        return font;
    }

    void onAssetsRequest()
    {
        // Add your assets here
    }

    void onLoading(float percentage)
    {
        // Render your loading screen here
    }

    void onAllocate()
    {
        // Allocate your objects here
    }

    void onRelease()
    {
        // Release your objects here
    }

    void onStart()
    {
        // Do your (re)initialization here
    }

    void onEnd()
    {
        // Do your finalization here
    }

    void onUpdate(double dt)
    {
        // Do your animation and logics here
    }

    void onRender()
    {
        // Do your rendering here
    }

    void exitApplication()
    {
        generateUserEvent(DagonEvent.Exit);
    }

    void load()
    {
        if (needToLoad)
        {
            onAssetsRequest();
            float p = assetManager.nextLoadingPercentage;

            assetManager.loadThreadSafePart();

            while(assetManager.isLoading)
            {
                sceneManager.application.beginRender();
                onLoading(p);
                sceneManager.application.endRender();
                p = assetManager.nextLoadingPercentage;
            }

            bool loaded = assetManager.loadThreadUnsafePart();
            
            if (loaded)
            {
                onAllocate();
                canRun = true;
                needToLoad = false;
            }
            else
            {
                writeln("Exiting due to error while loading assets");
                canRun = false;
                eventManager.running = false;
            }
        }
        else
        {
            canRun = true;
        }
    }

    void release()
    {
        onRelease();
        clearOwnedObjects();
        assetManager.releaseAssets();
        needToLoad = true;
        canRun = false;
    }

    void start()
    {
        if (canRun)
            onStart();
    }

    void end()
    {
        if (canRun)
            onEnd();
    }

    void update(double dt)
    {
        if (canRun)
        {
            processEvents();
            assetManager.updateMonitor(dt);
            onUpdate(dt);
        }

        if (releaseAtNextStep)
        {
            end();
            release();

            releaseAtNextStep = false;
            canRun = false;
        }
    }

    void render()
    {
        if (canRun)
            onRender();
    }
}

class SceneManager: Owner
{
    SceneApplication application;
    Dict!(Scene, string) scenesByName;
    EventManager eventManager;
    Scene currentScene;

    this(EventManager emngr, SceneApplication app)
    {
        super(app);
        application = app;
        eventManager = emngr;
        scenesByName = New!(Dict!(Scene, string));
    }

    ~this()
    {
        foreach(i, s; scenesByName)
        {
            Delete(s);
        }
        Delete(scenesByName);
    }

    Scene addScene(Scene scene, string name)
    {
        scenesByName[name] = scene;
        return scene;
    }

    void removeScene(string name)
    {
        Delete(scenesByName[name]);
        scenesByName.remove(name);
    }

    void goToScene(string name, bool releaseCurrent = true)
    {
        if (currentScene && releaseCurrent)
        {
            currentScene.releaseAtNextStep = true;
        }

        Scene scene = scenesByName[name];
        
        writefln("Loading scene \"%s\"", name);
        
        scene.load();
        currentScene = scene;
        currentScene.start();
        
        writefln("Running...", name);
    }

    void update(double dt)
    {
        if (currentScene)
        {
            currentScene.update(dt);
        }
    }

    void render()
    {
        if (currentScene)
        {
            currentScene.render();
        }
    } 
}

class SceneApplication: Application
{
    SceneManager sceneManager;

    this(uint w, uint h, bool fullscreen, string windowTitle, string[] args)
    {
        super(w, h, fullscreen, windowTitle, args);

        sceneManager = New!SceneManager(eventManager, this);
    }
    
    override void onUpdate(double dt)
    {
        sceneManager.update(dt);
    }
    
    override void onRender()
    {
        sceneManager.render();
    }
}

class BaseScene3D: Scene
{
    Environment environment;
    
    ClusteredLightManager lightManager;
    CascadedShadowMap shadowMap;

    BlinnPhongClusteredBackend defaultMaterialBackend;

    RenderingContext rc3d; 
    RenderingContext rc2d; 
    View view;

    DynamicArray!Entity entities3D;
    DynamicArray!Entity entities2D;
    
    ShapeQuad loadingProgressBar;
    Entity eLoadingProgressBar;
    HUDMaterialBackend hudMaterialBackend;
    GenericMaterial mLoadingProgressBar;

    double timer = 0.0;
    double fixedTimeStep = 1.0 / 60.0;

    this(SceneManager smngr)
    {
        super(smngr);
        
        rc3d.init(eventManager, environment);
        rc3d.projectionMatrix = perspectiveMatrix(60.0f, eventManager.aspectRatio, 0.1f, 1000.0f);

        rc2d.init(eventManager, environment);
        rc2d.projectionMatrix = orthoMatrix(0.0f, eventManager.windowWidth, 0.0f, eventManager.windowHeight, 0.0f, 100.0f);

        loadingProgressBar = New!ShapeQuad(assetManager);
        eLoadingProgressBar = New!Entity(eventManager, assetManager);
        eLoadingProgressBar.drawable = loadingProgressBar;
        hudMaterialBackend = New!HUDMaterialBackend(assetManager);
        mLoadingProgressBar = createMaterial(hudMaterialBackend);
        mLoadingProgressBar.diffuse = Color4f(1, 1, 1, 1);
        eLoadingProgressBar.material = mLoadingProgressBar;
    }

    Entity createEntity2D(Entity parent = null)
    {
        Entity e;
        if (parent)
            e = New!Entity(parent);
        else
        {
            e = New!Entity(eventManager, assetManager);
            entities2D.append(e);
        }
        
        return e;
    }
    
    Entity createEntity3D(Entity parent = null)
    {
        Entity e;
        if (parent)
            e = New!Entity(parent);
        else
        {
            e = New!Entity(eventManager, assetManager);
            entities3D.append(e);
        }
        return e;
    }
    
    GenericMaterial createMaterial(GenericMaterialBackend backend = null)
    {
        if (backend is null)
            backend = defaultMaterialBackend;
        return New!GenericMaterial(backend, assetManager);
    }
    
    LightSource createLight(Vector3f position, Color4f color, float volumeRadius, float areaRadius = 0.0f)
    {
        return lightManager.addLight(position, color, volumeRadius, areaRadius);
    }
    
    override void onAllocate()
    {    
        environment = New!Environment(assetManager);
        
        lightManager = New!ClusteredLightManager(200.0f, 100, assetManager);
        defaultMaterialBackend = New!BlinnPhongClusteredBackend(lightManager, assetManager);
        
        shadowMap = New!CascadedShadowMap(1024, this, 10, 50, 400, -100, 100, assetManager);
        defaultMaterialBackend.shadowMap = shadowMap;
    }
    
    override void onRelease()
    {
        entities3D.free();
        entities2D.free();
    }
    
    override void onLoading(float percentage)
    {
        glEnable(GL_SCISSOR_TEST);
        glScissor(0, 0, eventManager.windowWidth, eventManager.windowHeight);
        glViewport(0, 0, eventManager.windowWidth, eventManager.windowHeight);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        float maxWidth = eventManager.windowWidth * 0.33f;
        float x = (eventManager.windowWidth - maxWidth) * 0.5f;
        float y = eventManager.windowHeight * 0.5f - 10;
        float w = percentage * maxWidth;
        
        glDisable(GL_DEPTH_TEST);
        mLoadingProgressBar.diffuse = Color4f(0.1, 0.1, 0.1, 1);
        eLoadingProgressBar.position = Vector3f(x, y, 0);
        eLoadingProgressBar.scaling = Vector3f(maxWidth, 10, 1);
        eLoadingProgressBar.update(1.0/60.0);
        eLoadingProgressBar.render(&rc2d);
        
        mLoadingProgressBar.diffuse = Color4f(1, 1, 1, 1);
        eLoadingProgressBar.scaling = Vector3f(w, 10, 1);
        eLoadingProgressBar.update(1.0/60.0);
        eLoadingProgressBar.render(&rc2d);
    }

    override void onStart()
    {
        rc3d.initPerspective(eventManager, environment, 60.0f, 0.1f, 1000.0f);
        rc2d.initOrtho(eventManager, environment, 0.0f, 100.0f);

        timer = 0.0;
    }

    void onLogicsUpdate(double dt)
    {
    }

    override void onUpdate(double dt)
    {
        foreach(e; entities3D)
            e.processEvents();

        foreach(e; entities2D)
            e.processEvents();

        timer += dt;
        if (timer >= fixedTimeStep)
        {
            timer -= fixedTimeStep;

            if (view)
            {
                view.update(fixedTimeStep);
                view.prepareRC(&rc3d);
            }
            
            rc3d.time += fixedTimeStep;
            rc2d.time += fixedTimeStep;

            foreach(e; entities3D)
                e.update(fixedTimeStep);

            foreach(e; entities2D)
                e.update(fixedTimeStep);
                
            onLogicsUpdate(fixedTimeStep);
            
            environment.update(fixedTimeStep);
            
            if (view) // TODO: allow to turn this off
                shadowMap.position = view.cameraPosition;
            shadowMap.update(&rc3d, fixedTimeStep);
            
            lightManager.update(&rc3d);
        }
    }
    
    void renderShadows(RenderingContext* rc)
    {
        shadowMap.render(rc);
    }

    void renderEntities3D(RenderingContext* rc)
    {
        glEnable(GL_DEPTH_TEST);
        foreach(e; entities3D)
            e.render(rc);
    }

    void renderEntities2D(RenderingContext* rc)
    {
        glDisable(GL_DEPTH_TEST);
        foreach(e; entities2D)
            e.render(rc);
    }
    
    void prepareViewport()
    {
        glEnable(GL_SCISSOR_TEST);
        glScissor(0, 0, eventManager.windowWidth, eventManager.windowHeight);
        glViewport(0, 0, eventManager.windowWidth, eventManager.windowHeight);
        if (environment)
            glClearColor(environment.backgroundColor.r, environment.backgroundColor.g, environment.backgroundColor.b, environment.backgroundColor.a);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    }

    override void onRender()
    {
        renderShadows(&rc3d);
        
        prepareViewport();
        renderEntities3D(&rc3d);
        renderEntities2D(&rc2d);
    } 
}
