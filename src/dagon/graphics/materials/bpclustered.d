module dagon.graphics.materials.bpclustered;

import std.stdio;
import std.math;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.interpolation;
import dlib.image.color;
import dlib.image.unmanaged;
import dlib.image.render.shapes;

import derelict.opengl.gl;

import dagon.core.ownership;
import dagon.graphics.rc;
import dagon.graphics.shadow;
import dagon.graphics.clustered;
import dagon.graphics.texture;
import dagon.graphics.material;
import dagon.graphics.materials.generic;

class BlinnPhongClusteredBackend: GLSLMaterialBackend
{
    private string vsText = 
    q{
        #version 330 core
        
        uniform mat4 modelViewMatrix;
        uniform mat4 normalMatrix;
        uniform mat4 projectionMatrix;
        
        uniform mat4 invViewMatrix;
        
        uniform mat4 shadowMatrix1;
        uniform mat4 shadowMatrix2;
        uniform mat4 shadowMatrix3;
        
        layout (location = 0) in vec3 va_Vertex;
        layout (location = 1) in vec3 va_Normal;
        layout (location = 2) in vec2 va_Texcoord;
        
        out vec3 eyePosition;
        out vec3 eyeNormal;
        out vec2 texCoord;
        
        out vec3 worldPosition;
        
        out vec4 shadowCoord1;
        out vec4 shadowCoord2;
        out vec4 shadowCoord3;
        
        const float eyeSpaceNormalShift = 0.05;
        
        void main()
        {
            texCoord = va_Texcoord;
            eyeNormal = (normalMatrix * vec4(va_Normal, 0.0)).xyz;
            vec4 pos = modelViewMatrix * vec4(va_Vertex, 1.0);
            eyePosition = pos.xyz;
            
            worldPosition = (invViewMatrix * pos).xyz;
            
            vec4 posShifted = pos + vec4(eyeNormal * eyeSpaceNormalShift, 0.0);
            shadowCoord1 = shadowMatrix1 * posShifted;
            shadowCoord2 = shadowMatrix2 * posShifted;
            shadowCoord3 = shadowMatrix3 * posShifted;
            
            gl_Position = projectionMatrix * pos;
        }
    };

    private string fsText =
    q{
        #version 330 core
        
        uniform mat4 viewMatrix;
        uniform sampler2D diffuseTexture;
        uniform sampler2D normalTexture;
        uniform sampler2D heightTexture;
        
        uniform float roughness;
        
        uniform int parallaxMethod;
        uniform float parallaxScale;
        uniform float parallaxBias;
        
        uniform sampler2DArrayShadow shadowTextureArray;
        uniform float shadowTextureSize;
        uniform bool useShadows;
        
        uniform vec4 environmentColor;
        uniform vec3 sunDirection;
        uniform vec3 sunColor;
        uniform vec4 fogColor;
        uniform float fogStart;
        uniform float fogEnd;
        
        uniform float invLightDomainSize;
        uniform usampler2D lightClusterTexture;
        uniform usampler1D lightIndexTexture;
        uniform sampler2D lightsTexture;
        
        in vec3 eyePosition;
        in vec3 eyeNormal;
        in vec2 texCoord;
        
        in vec3 worldPosition;
        
        in vec4 shadowCoord1;
        in vec4 shadowCoord2;
        in vec4 shadowCoord3;
        
        out vec4 frag_color;
        
        mat3 cotangentFrame(in vec3 N, in vec3 p, in vec2 uv)
        {
            vec3 dp1 = dFdx(p);
            vec3 dp2 = dFdy(p);
            vec2 duv1 = dFdx(uv);
            vec2 duv2 = dFdy(uv);
            vec3 dp2perp = cross(dp2, N);
            vec3 dp1perp = cross(N, dp1);
            vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
            vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
            float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
            return mat3(T * invmax, B * invmax, N);
        }
        
        vec2 parallaxMapping(in vec3 V, in vec2 T, in float scale)
        {
            float height = texture(heightTexture, T).r;
            height = height * parallaxScale + parallaxBias;
            return T + (height * V.xy);
        }
        
        // Based on code written by Igor Dykhta (Sun and Black Cat)
        // http://sunandblackcat.com/tipFullView.php?topicid=28
        vec2 parallaxOcclusionMapping(in vec3 V, in vec2 T, in float scale)
        {
            const float minLayers = 10;
            const float maxLayers = 15;
            float numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0, 0, 1), V)));

            float layerHeight = 1.0 / numLayers;
            float curLayerHeight = 0;
            vec2 dtex = scale * V.xy / V.z / numLayers;

            vec2 currentTextureCoords = T;
            float heightFromTexture = texture(heightTexture, currentTextureCoords).r;

            while(heightFromTexture > curLayerHeight)
            {
                curLayerHeight += layerHeight;
                currentTextureCoords += dtex;
                heightFromTexture = texture(heightTexture, currentTextureCoords).r;
            }

            vec2 prevTCoords = currentTextureCoords - dtex;

            float nextH = heightFromTexture - curLayerHeight;
            float prevH = texture(heightTexture, prevTCoords).r - curLayerHeight + layerHeight;
            float weight = nextH / (nextH - prevH);
            return prevTCoords * weight + currentTextureCoords * (1.0-weight);
        }
        
        float shadowLookup(in sampler2DArrayShadow depths, in float layer, in vec4 coord, in vec2 offset)
        {
            float texelSize = 1.0 / shadowTextureSize;
            vec2 v = offset * texelSize * coord.w;
            vec4 c = (coord + vec4(v.x, v.y, 0.0, 0.0)) / coord.w;
            c.w = c.z;
            c.z = layer;
            float s = texture(depths, c);
            return s;
        }
        
        float pcf(in sampler2DArrayShadow depths, in float layer, in vec4 coord, in float radius, in float yshift)
        {
            float s = 0.0;
            float x, y;
	        for (y = -radius ; y < radius ; y += 1.0)
	        for (x = -radius ; x < radius ; x += 1.0)
            {
	            s += shadowLookup(depths, layer, coord, vec2(x, y + yshift));
            }
	        s /= radius * radius * 4.0;
            return s;
        }
        
        float weight(in vec4 tc)
        {
            vec2 proj = vec2(tc.x / tc.w, tc.y / tc.w);
            proj = (1.0 - abs(proj * 2.0 - 1.0)) * 8.0;
            proj = clamp(proj, 0.0, 1.0);
            return min(proj.x, proj.y);
        }
        
        void main()
        {
            // Common vectors
            vec3 N = normalize(eyeNormal);
            vec3 E = normalize(-eyePosition);
            mat3 TBN = cotangentFrame(eyeNormal, eyePosition, texCoord);
            vec3 tE = normalize(E * TBN);

            // Parallax mapping
            vec2 shiftedTexCoord = texCoord;
            if (parallaxMethod == 0)
                shiftedTexCoord = texCoord;
            else if (parallaxMethod == 1)
                shiftedTexCoord = parallaxMapping(tE, texCoord, parallaxScale);
            else if (parallaxMethod == 2)
                shiftedTexCoord = parallaxOcclusionMapping(tE, texCoord, parallaxScale);
            
            // Normal mapping
            vec3 tN = normalize(texture2D(normalTexture, shiftedTexCoord).rgb * 2.0 - 1.0);
            tN.y = -tN.y;
            N = normalize(TBN * tN);

            // Roughness to blinn-phong specular power
            float gloss = 1.0 - roughness;
            float shininess = gloss * 128.0;
            
            // Sun light
            float sunDiffBrightness = clamp(dot(N, sunDirection), 0.0, 1.0);
            vec3 halfEye = normalize(sunDirection + E);
            float NH = dot(N, halfEye);
            float sunSpecBrightness = pow(max(NH, 0.0), shininess) * gloss;
            
            // Calculate shadow from 3 cascades
            float s1, s2, s3;
            if (useShadows)
            {
                s1 = pcf(shadowTextureArray, 0.0, shadowCoord1, 3.0, 0.0);
                s2 = pcf(shadowTextureArray, 1.0, shadowCoord2, 2.0, 0.0);
                s3 = pcf(shadowTextureArray, 2.0, shadowCoord3, 1.0, 0.0);
                float w1 = weight(shadowCoord1);
                float w2 = weight(shadowCoord2);
                float w3 = weight(shadowCoord3);
                s3 = mix(1.0, s3, w3); 
                s2 = mix(s3, s2, w2);
                s1 = mix(s2, s1, w1); // s1 stores resulting shadow value
            }
            else
            {
                s1 = 1.0f;
            }
            
            // Fetch light cluster slice
            vec2 clusterCoord = worldPosition.xz * invLightDomainSize + 0.5;
            uint clusterIndex = texture(lightClusterTexture, clusterCoord).r;
            uint offset = (clusterIndex << 16) >> 16;
            uint size = (clusterIndex >> 16);
            
            vec3 pointDiffSum = vec3(0.0, 0.0, 0.0);
            vec3 pointSpecSum = vec3(0.0, 0.0, 0.0);
            for (uint i = 0u; i < size; i++)
            {
                // Read light data
                uint u = texelFetch(lightIndexTexture, int(offset + i), 0).r;
                vec3 lightPos = texelFetch(lightsTexture, ivec2(u, 0), 0).xyz; 
                vec3 lightColor = texelFetch(lightsTexture, ivec2(u, 1), 0).xyz; 
                vec3 lightProps = texelFetch(lightsTexture, ivec2(u, 2), 0).xyz;
                float lightRadius = lightProps.x;
                float lightAreaRadius = lightProps.y;
                float lightEnergy = lightProps.z;
                
                lightPos = (viewMatrix * vec4(lightPos, 1.0)).xyz;
                
                vec3 lightPos2 = (viewMatrix * vec4(lightPos + vec3(0.0, 0.0, 1.0), 1.0)).xyz;
                
                vec3 positionToLightSource = lightPos - eyePosition;
                float distanceToLight = length(positionToLightSource);
                vec3 directionToLight = normalize(positionToLightSource);
                
                vec3 r = reflect(E, N);
                
	            vec3 centerToRay = dot(positionToLightSource, r) * r - positionToLightSource;
	            vec3 closestPoint = positionToLightSource + centerToRay * clamp(lightAreaRadius / length(centerToRay), 0.0, 1.0);	
	            directionToLight = normalize(closestPoint);

                float attenuation = clamp(1.0 - (distanceToLight / lightRadius), 0.0, 1.0) * lightEnergy;
                
                float NH = dot(N, normalize(directionToLight + E));
                float spec = pow(max(NH, 0.0), shininess) * gloss;
                float diff = clamp(dot(N, directionToLight), 0.0, 1.0) - spec;
                
                pointDiffSum += lightColor * diff * attenuation;
                pointSpecSum += lightColor * spec * attenuation;
            }
            
            // Fog
            float fogDistance = gl_FragCoord.z / gl_FragCoord.w;
            float fogFactor = clamp((fogEnd - fogDistance) / (fogEnd - fogStart), 0.0, 1.0);
            
            // Diffuse texture
            vec4 diffuseColor = texture(diffuseTexture, shiftedTexCoord);

            vec3 objColor = diffuseColor.rgb * (environmentColor.rgb + pointDiffSum + sunColor * sunDiffBrightness * s1) + 
                pointSpecSum + sunColor * sunSpecBrightness * s1;
                
            vec3 fragColor = mix(fogColor.rgb, objColor, fogFactor);
            
            frag_color = vec4(fragColor, diffuseColor.a);
        }
    };
    
    override string vertexShaderSrc() {return vsText;}
    override string fragmentShaderSrc() {return fsText;}

    GLint viewMatrixLoc;
    GLint modelViewMatrixLoc;
    GLint projectionMatrixLoc;
    GLint normalMatrixLoc;
    GLint invViewMatrixLoc;
    
    GLint shadowMatrix1Loc;
    GLint shadowMatrix2Loc; 
    GLint shadowMatrix3Loc;
    GLint shadowTextureArrayLoc;
    GLint shadowTextureSizeLoc;
    GLint useShadowsLoc;
    
    GLint roughnessLoc;
    
    GLint parallaxMethodLoc;
    GLint parallaxScaleLoc;
    GLint parallaxBiasLoc;
    
    GLint diffuseTextureLoc;
    GLint normalTextureLoc;
    GLint heightTextureLoc;
    
    GLint environmentColorLoc;
    GLint sunDirectionLoc;
    GLint sunColorLoc;
    GLint fogStartLoc;
    GLint fogEndLoc;
    GLint fogColorLoc;
    
    GLint invLightDomainSizeLoc;
    GLint clusterTextureLoc;
    GLint lightsTextureLoc;
    //GLint locLightTextureWidth;
    GLint indexTextureLoc;
    //GLint locIndexTextureWidth;
    
    ClusteredLightManager lightManager;
    CascadedShadowMap shadowMap;
    Matrix4x4f defaultShadowMat;
    Vector3f defaultLightDir;
    
    this(ClusteredLightManager clm, Owner o)
    {
        super(o);
        
        lightManager = clm;

        viewMatrixLoc = glGetUniformLocation(shaderProgram, "viewMatrix");
        modelViewMatrixLoc = glGetUniformLocation(shaderProgram, "modelViewMatrix");
        projectionMatrixLoc = glGetUniformLocation(shaderProgram, "projectionMatrix");
        normalMatrixLoc = glGetUniformLocation(shaderProgram, "normalMatrix");
        invViewMatrixLoc = glGetUniformLocation(shaderProgram, "invViewMatrix");
        
        shadowMatrix1Loc = glGetUniformLocation(shaderProgram, "shadowMatrix1");
        shadowMatrix2Loc = glGetUniformLocation(shaderProgram, "shadowMatrix2");
        shadowMatrix3Loc = glGetUniformLocation(shaderProgram, "shadowMatrix3");
        shadowTextureArrayLoc = glGetUniformLocation(shaderProgram, "shadowTextureArray");
        shadowTextureSizeLoc = glGetUniformLocation(shaderProgram, "shadowTextureSize");
        useShadowsLoc = glGetUniformLocation(shaderProgram, "useShadows");
        
        roughnessLoc = glGetUniformLocation(shaderProgram, "roughness"); 
       
        parallaxMethodLoc = glGetUniformLocation(shaderProgram, "parallaxMethod");
        parallaxScaleLoc = glGetUniformLocation(shaderProgram, "parallaxScale");
        parallaxBiasLoc = glGetUniformLocation(shaderProgram, "parallaxBias");
        
        diffuseTextureLoc = glGetUniformLocation(shaderProgram, "diffuseTexture");
        normalTextureLoc = glGetUniformLocation(shaderProgram, "normalTexture");
        heightTextureLoc = glGetUniformLocation(shaderProgram, "heightTexture");
        
        environmentColorLoc = glGetUniformLocation(shaderProgram, "environmentColor");
        sunDirectionLoc = glGetUniformLocation(shaderProgram, "sunDirection");
        sunColorLoc = glGetUniformLocation(shaderProgram, "sunColor");
        fogStartLoc = glGetUniformLocation(shaderProgram, "fogStart");
        fogEndLoc = glGetUniformLocation(shaderProgram, "fogEnd");
        fogColorLoc = glGetUniformLocation(shaderProgram, "fogColor");
        
        clusterTextureLoc = glGetUniformLocation(shaderProgram, "lightClusterTexture");
        invLightDomainSizeLoc = glGetUniformLocation(shaderProgram, "invLightDomainSize");
        lightsTextureLoc = glGetUniformLocation(shaderProgram, "lightsTexture");
        indexTextureLoc = glGetUniformLocation(shaderProgram, "lightIndexTexture");
    }
    
    Texture makeOnePixelTexture(Material mat, Color4f color)
    {
        auto img = New!UnmanagedImageRGBA8(8, 8);
        img.fillColor(color);
        auto tex = New!Texture(img, mat, false);
        Delete(img);
        return tex;
    }
    
    override void bind(GenericMaterial mat, RenderingContext* rc)
    {
        auto idiffuse = "diffuse" in mat.inputs;
        auto inormal = "normal" in mat.inputs;
        auto iheight = "height" in mat.inputs;
        auto iroughness = "roughness" in mat.inputs;
        bool fogEnabled = boolProp(mat, "fogEnabled");
        bool shadowsEnabled = boolProp(mat, "shadowsEnabled");
        int parallaxMethod = intProp(mat, "parallax");
        if (parallaxMethod > ParallaxOcclusionMapping)
            parallaxMethod = ParallaxOcclusionMapping;
        if (parallaxMethod < 0)
            parallaxMethod = 0;
        
        glUseProgram(shaderProgram);
        
        // Matrices
        glUniformMatrix4fv(viewMatrixLoc, 1, GL_FALSE, rc.viewMatrix.arrayof.ptr);
        glUniformMatrix4fv(modelViewMatrixLoc, 1, GL_FALSE, rc.modelViewMatrix.arrayof.ptr);
        glUniformMatrix4fv(projectionMatrixLoc, 1, GL_FALSE, rc.projectionMatrix.arrayof.ptr);
        glUniformMatrix4fv(normalMatrixLoc, 1, GL_FALSE, rc.normalMatrix.arrayof.ptr);
        glUniformMatrix4fv(invViewMatrixLoc, 1, GL_FALSE, rc.invViewMatrix.arrayof.ptr);
        
        // Environment parameters
        Color4f environmentColor = Color4f(0.0f, 0.0f, 0.0f, 1.0f);
        Vector4f sunHGVector = Vector4f(0.0f, 1.0f, 0.0, 0.0f);
        Vector3f sunColor = Vector3f(1.0f, 1.0f, 1.0f);
        if (rc.environment)
        {
            environmentColor = rc.environment.ambientConstant;
            sunHGVector = Vector4f(rc.environment.sunDirection);
            sunHGVector.w = 0.0;
            sunColor = rc.environment.sunColor;
        }
        glUniform4fv(environmentColorLoc, 1, environmentColor.arrayof.ptr);
        Vector3f sunDirectionEye = sunHGVector * rc.viewMatrix;
        glUniform3fv(sunDirectionLoc, 1, sunDirectionEye.arrayof.ptr);
        glUniform3fv(sunColorLoc, 1, sunColor.arrayof.ptr);
        Color4f fogColor = Color4f(0.0f, 0.0f, 0.0f, 1.0f);
        float fogStart = float.max;
        float fogEnd = float.max;
        if (fogEnabled)
        {
            if (rc.environment)
            {                
                fogColor = rc.environment.fogColor;
                fogStart = rc.environment.fogStart;
                fogEnd = rc.environment.fogEnd;
            }
        }
        glUniform4fv(fogColorLoc, 1, fogColor.arrayof.ptr);
        glUniform1f(fogStartLoc, fogStart);
        glUniform1f(fogEndLoc, fogEnd);
        
        // PBR parameters
        glUniform1f(roughnessLoc, iroughness.asFloat);
        
        // Parallax mapping parameters
        float parallaxScale = 0.0f;
        float parallaxBias = 0.0f;
        if (iheight.texture is null)
        {
            // These is for simple parallax mapping:
            Color4f color = Color4f(0.0, 0.0, 0.0, 0);
            iheight.texture = makeOnePixelTexture(mat, color);
        }
        else
        {          
            parallaxScale = 0.03f;
            parallaxBias = -0.01f;
        }
        glUniform1f(parallaxScaleLoc, parallaxScale);
        glUniform1f(parallaxBiasLoc, parallaxBias);
        glUniform1i(parallaxMethodLoc, parallaxMethod);
        
        // Texture 0 - diffuse texture
        if (idiffuse.texture is null)
        {
            Color4f color = Color4f(idiffuse.asVector4f);
            idiffuse.texture = makeOnePixelTexture(mat, color);
        }
        glActiveTexture(GL_TEXTURE0);
        idiffuse.texture.bind();
        glUniform1i(diffuseTextureLoc, 0);
        
        // Texture 1 - normal map
        if (inormal.texture is null)
        {
            Color4f color = Color4f(0.5f, 0.5f, 1.0f); // default normal pointing upwards
            inormal.texture = makeOnePixelTexture(mat, color);
        }
        glActiveTexture(GL_TEXTURE1);
        inormal.texture.bind();
        glUniform1i(normalTextureLoc, 1);
        
        // Texture 2 - height map
        // TODO: pass height data as an alpha channel of normap map, 
        // thus releasing space for some additional texture
        glActiveTexture(GL_TEXTURE2);
        iheight.texture.bind();
        glUniform1i(heightTextureLoc, 2);
        
        // Texture 3 - shadow map cascades (3 layer texture array)
        if (shadowMap && shadowsEnabled)
        {
            glActiveTexture(GL_TEXTURE3);
            glBindTexture(GL_TEXTURE_2D_ARRAY, shadowMap.depthTexture);

            glUniform1i(shadowTextureArrayLoc, 3);
            glUniform1f(shadowTextureSizeLoc, cast(float)shadowMap.size);
            glUniformMatrix4fv(shadowMatrix1Loc, 1, 0, shadowMap.area1.shadowMatrix.arrayof.ptr);
            glUniformMatrix4fv(shadowMatrix2Loc, 1, 0, shadowMap.area2.shadowMatrix.arrayof.ptr);
            glUniformMatrix4fv(shadowMatrix3Loc, 1, 0, shadowMap.area3.shadowMatrix.arrayof.ptr);
            glUniform1i(useShadowsLoc, 1);
            
            // TODO: shadowFilter
        }
        else
        {        
            glUniformMatrix4fv(shadowMatrix1Loc, 1, 0, defaultShadowMat.arrayof.ptr);
            glUniformMatrix4fv(shadowMatrix2Loc, 1, 0, defaultShadowMat.arrayof.ptr);
            glUniformMatrix4fv(shadowMatrix3Loc, 1, 0, defaultShadowMat.arrayof.ptr);
            glUniform1i(useShadowsLoc, 0);
        }
        
        // Texture 4 is reserved for PBR maps (roughness + metallic + emission)
        // Texture 5 is reserved for environment map

        // Texture 6 - light clusters
        glActiveTexture(GL_TEXTURE6);
        lightManager.bindClusterTexture();
        glUniform1i(clusterTextureLoc, 6);
        glUniform1f(invLightDomainSizeLoc, lightManager.invSceneSize);
        
        // Texture 7 - light data
        glActiveTexture(GL_TEXTURE7);
        lightManager.bindLightTexture();
        glUniform1i(lightsTextureLoc, 7);
        
        // Texture 8 - light indices per cluster
        glActiveTexture(GL_TEXTURE8);
        lightManager.bindIndexTexture();
        glUniform1i(indexTextureLoc, 8);
        
        glActiveTexture(GL_TEXTURE0);
    }
    
    override void unbind(GenericMaterial mat)
    {
        auto idiffuse = "diffuse" in mat.inputs;
        auto inormal = "normal" in mat.inputs;
        auto iheight = "height" in mat.inputs;
        
        glActiveTexture(GL_TEXTURE0);
        idiffuse.texture.unbind();
        
        glActiveTexture(GL_TEXTURE1);
        inormal.texture.unbind();
        
        glActiveTexture(GL_TEXTURE2);
        iheight.texture.unbind();
        
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D_ARRAY, 0);
        
        glActiveTexture(GL_TEXTURE6);
        lightManager.unbindClusterTexture();
        
        glActiveTexture(GL_TEXTURE7);
        lightManager.unbindLightTexture();
        
        glActiveTexture(GL_TEXTURE8);
        lightManager.unbindIndexTexture();
        
        glActiveTexture(GL_TEXTURE0);
        
        glUseProgram(0);
    }
}