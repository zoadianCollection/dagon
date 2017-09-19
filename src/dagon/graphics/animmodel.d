module dagon.graphics.animmodel;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import derelict.opengl.gl;
import dagon.core.interfaces;
import dagon.core.ownership;
import dagon.graphics.texture;
import dagon.graphics.mesh;

interface AnimatedModel
{
    void calcBindPose(AnimationFrameData* data);
    void calcFrame(uint f1, uint f2, float t, AnimationFrameData* data);
    void blendFrame(uint f1, uint f2, float t, AnimationFrameData* data, float blendFactor);
    Vector3f[] getVertices();
    Vector3f[] getNormals();
    Vector2f[] getTexcoords();
    uint[3][] getTriangles();
    AnimationFacegroup[] getFacegroups();
    size_t numBones();
    bool getAnimation(string name, AnimationData* data);
    uint numAnimationFrames();
}

struct AnimationFacegroup
{
    size_t firstTriangle;
    size_t numTriangles;
    Texture texture;
    string textureName;
}

struct AnimationData
{
    uint firstFrame;
    uint numFrames;
    float framerate;
}

struct AnimationFrameData
{
    Vector3f[] vertices;
    Vector3f[] normals;
    Vector2f[] texcoords;
    uint[3][] tris;
    Matrix4x4f[] frame;
}

struct ActorState
{
    uint currentFrame = 0;
    uint nextFrame = 1;
    float t = 0.0f;
}

class Actor: Owner, Drawable
{
    AnimatedModel model;
    AnimationFrameData frameData;
    AnimationData animation;
    AnimationData nextAnimation;
    bool hasNextAnimation = false;
    float blendFactor = 0.0f;
    ActorState state;
    ActorState nextState;
    bool playing = false;
    float defaultFramerate = 24.0f;
    float speed = 1.0f;
    bool swapZY = true;
    
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint nbo = 0;
    GLuint tbo = 0;
    GLuint eao = 0;

    this(AnimatedModel m, Owner owner)
    {
        super(owner);
        model = m;

        if (model.getVertices().length)
            frameData.vertices = New!(Vector3f[])(model.getVertices().length);
        if (model.getNormals().length)
            frameData.normals = New!(Vector3f[])(model.getNormals().length);
        if (model.getTexcoords().length)
            frameData.texcoords = model.getTexcoords(); // no need to make a copy, texcoords don't change frame to frame
        if (model.getTriangles().length)
            frameData.tris = model.getTriangles(); // no need to make a copy, indices don't change frame to frame
        if (model.numBones())
            frameData.frame = New!(Matrix4x4f[])(model.numBones());

        model.calcBindPose(&frameData);

        switchToFullSequence();
        
        foreach(ref v; frameData.vertices)
            v = Vector3f(0, 0, 0);
            
        foreach(ref n; frameData.normals)
            n = Vector3f(0, 0, 0);
        
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, frameData.vertices.length * float.sizeof * 3, frameData.vertices.ptr, GL_DYNAMIC_DRAW); 

        glGenBuffers(1, &nbo);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glBufferData(GL_ARRAY_BUFFER, frameData.normals.length * float.sizeof * 3, frameData.normals.ptr, GL_DYNAMIC_DRAW);

        glGenBuffers(1, &tbo);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glBufferData(GL_ARRAY_BUFFER, frameData.texcoords.length * float.sizeof * 2, frameData.texcoords.ptr, GL_DYNAMIC_DRAW);

        glGenBuffers(1, &eao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, frameData.tris.length * uint.sizeof * 3, frameData.tris.ptr, GL_DYNAMIC_DRAW);
        
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
    
        glEnableVertexAttribArray(VertexAttrib.Vertices);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(VertexAttrib.Vertices, 3, GL_FLOAT, GL_FALSE, 0, null);
    
        glEnableVertexAttribArray(VertexAttrib.Normals);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glVertexAttribPointer(VertexAttrib.Normals, 3, GL_FLOAT, GL_FALSE, 0, null);
    
        glEnableVertexAttribArray(VertexAttrib.Texcoords);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glVertexAttribPointer(VertexAttrib.Texcoords, 2, GL_FLOAT, GL_FALSE, 0, null);
        
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

        glBindVertexArray(0);
    }

    ~this()
    {
        if (frameData.vertices.length) Delete(frameData.vertices);
        if (frameData.normals.length) Delete(frameData.normals);
        if (frameData.frame.length) Delete(frameData.frame);
    }

    void switchToBindPose()
    {
        model.calcBindPose(&frameData);
        playing = false;
    }

    void switchToAnimation(string name)
    {
        model.getAnimation(name, &animation);
        state.currentFrame = animation.firstFrame;
        state.nextFrame = state.currentFrame + 1;
        state.t = 0.0f;
    }

    void switchToAnimationSmooth(string name, float smooth)
    {
        model.getAnimation(name, &nextAnimation);
        hasNextAnimation = true;
        nextState.currentFrame = nextAnimation.firstFrame;
        nextState.nextFrame = nextState.currentFrame + 1;
        nextState.t = 0.0f;
    }

    void switchToSequence(uint startFrame, uint endFrame)
    {
        //model.getAnimation(name, &nextAnimation);
        animation.firstFrame = startFrame;
        animation.numFrames = endFrame - startFrame;
        state.currentFrame = animation.firstFrame;
        state.nextFrame = state.currentFrame + 1;
        state.t = 0.0f;
    }

    void switchToSequenceSmooth(uint startFrame, uint endFrame, float smooth)
    {
        //model.getAnimation(name, &nextAnimation);
        nextAnimation.firstFrame = startFrame;
        nextAnimation.numFrames = endFrame - startFrame;
        hasNextAnimation = true;
        nextState.currentFrame = nextAnimation.firstFrame;
        nextState.nextFrame = nextState.currentFrame + 1;
        nextState.t = 0.0f;
    }

    void switchToFullSequence()
    {
        switchToAnimation("");
        animation.framerate = defaultFramerate;
        state.currentFrame = animation.firstFrame;
        state.nextFrame = state.currentFrame + 1;
        state.t = 0.0f;
    }

    void play()
    {
        playing = true;
    }

    void pause()
    {
        playing = false;
    }

    void update(double dt)
    {
        if (!playing)
            return;

        model.calcFrame(state.currentFrame, state.nextFrame, state.t, &frameData);

        state.t += defaultFramerate * dt * speed; //animation.framerate

        if (state.t >= 1.0f)
        {
            state.t = 0.0f;
            state.currentFrame++;
            state.nextFrame++;

            if (state.currentFrame == animation.firstFrame + animation.numFrames - 1)
            {
                state.nextFrame = animation.firstFrame;
            }
            else if (state.currentFrame == animation.firstFrame + animation.numFrames)
            {
                state.currentFrame = animation.firstFrame;
                state.nextFrame = state.currentFrame + 1;
            }
        }

        if (hasNextAnimation)
        {
            model.blendFrame(nextState.currentFrame, nextState.nextFrame, nextState.t, &frameData, blendFactor);
            nextState.t += defaultFramerate * dt * speed; //nextAnimation.framerate
            blendFactor += dt; // TODO: time multiplier

            if (nextState.t >= 1.0f)
            {
                nextState.t = 0.0f;
                nextState.currentFrame++;
                nextState.nextFrame++;

                if (nextState.currentFrame == nextAnimation.numFrames - 1)
                {
                    nextState.nextFrame = nextAnimation.firstFrame;
                }
                else if (nextState.currentFrame == nextAnimation.numFrames)
                {
                    nextState.currentFrame = nextAnimation.firstFrame;
                    nextState.nextFrame = nextState.currentFrame + 1;
                }
            }

            if (blendFactor >= 1.0f)
            {
                blendFactor = 0.0f;
                hasNextAnimation = false;
                animation = nextAnimation;
                state = nextState;
            }
        }
        
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferSubData(GL_ARRAY_BUFFER, 0, frameData.vertices.length * float.sizeof * 3, frameData.vertices.ptr);
        glBindBuffer(GL_ARRAY_BUFFER, nbo);
        glBufferSubData(GL_ARRAY_BUFFER, 0, frameData.normals.length * float.sizeof * 3, frameData.normals.ptr);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }

    void render(RenderingContext* rc)
    {
        glDisable(GL_CULL_FACE);
        glBindVertexArray(vao);
        foreach(ref fg; model.getFacegroups)
        {
            glActiveTexture(GL_TEXTURE0);
            if (fg.texture)
                fg.texture.bind();
            glDrawElements(GL_TRIANGLES, cast(uint)(3 * fg.numTriangles), GL_UNSIGNED_INT, &frameData.tris[fg.firstTriangle]);
            if (fg.texture)
                fg.texture.unbind();
        }
        glBindVertexArray(0);
    }
}