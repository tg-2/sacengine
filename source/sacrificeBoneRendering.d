module sacrificeBoneRendering;

import dlib.math.matrix;
import dlib.math.vector;
import derelict.opengl;

import dagon.core.ownership : Owner;
import dagon.graphics.boneMesh : DagonBoneMesh = BoneMesh;
import dagon.graphics.materials.bone : DagonBoneBackend = BoneBackend;
import dagon.graphics.materials.shadelessBone : DagonShadelessBoneBackend = ShadelessBoneBackend;
import dagon.graphics.rc : RenderingContext;
import dagon.graphics.shadow : DagonBoneShadowBackend = BoneShadowBackend;

class SacrificeBoneMesh: DagonBoneMesh
{
    bool retailSourceNormals = false;
    static bool hideSxmdSeams = false;
    size_t seamFaceStart = 0;
    size_t seamFaceCount = 0;

    this(Owner owner)
    {
        super(owner);
    }

    override void render(RenderingContext* rc)
    {
        if (!canRender)
            return;

        glBindVertexArray(vao);
        if (hideSxmdSeams && seamFaceCount != 0)
        {
            assert(seamFaceStart <= indices.length);
            assert(seamFaceCount <= indices.length - seamFaceStart);

            if (seamFaceStart != 0)
                glDrawElements(GL_TRIANGLES, cast(uint)seamFaceStart * 3,
                    GL_UNSIGNED_INT, cast(void*)0);

            const size_t after = seamFaceStart + seamFaceCount;
            if (after < indices.length)
                glDrawElements(GL_TRIANGLES, cast(uint)(indices.length - after) * 3,
                    GL_UNSIGNED_INT, cast(void*)(after * 3 * uint.sizeof));
        }
        else
        {
            glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3,
                GL_UNSIGNED_INT, cast(void*)0);
        }
        glBindVertexArray(0);
    }
}

class SacrificeBoneBackend: DagonBoneBackend
{
    private string sacrificeVertexShader = `
        #version 330 core
        precision highp float;

        uniform mat4 modelViewMatrix;
        uniform mat4 projectionMatrix;
        uniform mat4 normalMatrix;
        uniform mat4 prevModelViewProjMatrix;
        uniform mat4 blurModelViewProjMatrix;
        uniform mat4 pose[32];
        uniform bool retailSourceNormals;
        uniform vec3 rootOffset;
        uniform float bulk;

        layout (location = 0) in vec3 va_Vertex0;
        layout (location = 1) in vec3 va_Vertex1;
        layout (location = 2) in vec3 va_Vertex2;
        layout (location = 3) in vec3 va_Normal;
        layout (location = 4) in vec2 va_Texcoord;
        layout (location = 5) in uvec3 va_BoneIndices;
        layout (location = 6) in vec3 va_Weights;

        out vec2 texCoord;
        out vec3 eyePosition;
        out vec3 eyeNormal;
        out vec4 blurPosition;
        out vec4 prevPosition;

        void main()
        {
            texCoord = va_Texcoord;
            vec4 newNormal = (pose[va_BoneIndices.x] * va_Weights.x
                           +  pose[va_BoneIndices.y] * va_Weights.y
                           +  pose[va_BoneIndices.z] * va_Weights.z)
                           * vec4(va_Normal, 0.0);
            if (retailSourceNormals)
                newNormal = pose[va_BoneIndices.x] * vec4(va_Normal, 0.0);
            eyeNormal = (normalMatrix * newNormal).xyz;

            vec4 newVertex = pose[va_BoneIndices.x] * vec4(bulk * va_Vertex0, 1.0) * va_Weights.x
                           + pose[va_BoneIndices.y] * vec4(bulk * va_Vertex1, 1.0) * va_Weights.y
                           + pose[va_BoneIndices.z] * vec4(bulk * va_Vertex2, 1.0) * va_Weights.z;
            newVertex.xyz += rootOffset;

            vec4 pos = modelViewMatrix * vec4(newVertex.xyz, 1.0);
            eyePosition = pos.xyz;
            gl_Position = projectionMatrix * pos;
            blurPosition = blurModelViewProjMatrix * vec4(newVertex.xyz, 1.0);
            prevPosition = prevModelViewProjMatrix * vec4(newVertex.xyz, 1.0);
        }
    `;

    private GLint retailSourceNormalsLoc;
    private GLint rootOffsetLoc;

    override string vertexShaderSrc()
    {
        return sacrificeVertexShader;
    }

    this(Owner owner)
    {
        super(owner);
        retailSourceNormalsLoc = glGetUniformLocation(shaderProgram, "retailSourceNormals");
        rootOffsetLoc = glGetUniformLocation(shaderProgram, "rootOffset");
    }

    void setPose(Matrix4x4f[] pose,
        Vector3f rootOffset = Vector3f(0.0f, 0.0f, 0.0f),
        bool retailSourceNormals = false)
    {
        super.setPose(pose);
        glUniform1i(retailSourceNormalsLoc, retailSourceNormals);
        glUniform3fv(rootOffsetLoc, 1, rootOffset.arrayof.ptr);
    }
}

class SacrificeShadelessBoneBackend: DagonShadelessBoneBackend
{
    private string sacrificeVertexShader = `
        #version 330 core
        precision highp float;

        layout (location = 0) in vec3 va_Vertex0;
        layout (location = 1) in vec3 va_Vertex1;
        layout (location = 2) in vec3 va_Vertex2;
        layout (location = 4) in vec2 va_Texcoord;
        layout (location = 5) in uvec3 va_BoneIndices;
        layout (location = 6) in vec3 va_Weights;

        out vec2 texCoord;
        uniform mat4 modelViewMatrix;
        uniform mat4 projectionMatrix;
        uniform mat4 pose[32];
        uniform vec3 rootOffset;
        uniform float bulk;

        void main()
        {
            vec4 newVertex = pose[va_BoneIndices.x] * vec4(bulk * va_Vertex0, 1.0) * va_Weights.x
                           + pose[va_BoneIndices.y] * vec4(bulk * va_Vertex1, 1.0) * va_Weights.y
                           + pose[va_BoneIndices.z] * vec4(bulk * va_Vertex2, 1.0) * va_Weights.z;
            newVertex.xyz += rootOffset;
            vec4 pos = modelViewMatrix * vec4(newVertex.xyz, 1.0);
            texCoord = va_Texcoord;
            gl_Position = projectionMatrix * pos;
        }
    `;

    private GLint rootOffsetLoc;

    override string vertexShaderSrc()
    {
        return sacrificeVertexShader;
    }

    this(Owner owner)
    {
        super(owner);
        rootOffsetLoc = glGetUniformLocation(shaderProgram, "rootOffset");
    }

    void setPose(Matrix4x4f[] pose,
        Vector3f rootOffset = Vector3f(0.0f, 0.0f, 0.0f))
    {
        super.setPose(pose);
        glUniform3fv(rootOffsetLoc, 1, rootOffset.arrayof.ptr);
    }
}

class SacrificeBoneShadowBackend: DagonBoneShadowBackend
{
    private string sacrificeVertexShader = `
        #version 330 core
        precision highp float;

        uniform mat4 modelViewMatrix;
        uniform mat4 projectionMatrix;
        uniform mat4 pose[32];
        uniform vec3 rootOffset;
        uniform float bulk;

        layout (location = 0) in vec3 va_Vertex0;
        layout (location = 1) in vec3 va_Vertex1;
        layout (location = 2) in vec3 va_Vertex2;
        layout (location = 4) in vec2 va_Texcoord;
        layout (location = 5) in uvec3 va_BoneIndices;
        layout (location = 6) in vec3 va_Weights;
        out vec2 texCoord;

        void main()
        {
            texCoord = va_Texcoord;
            vec4 newVertex = pose[va_BoneIndices.x] * vec4(bulk * va_Vertex0, 1.0) * va_Weights.x
                           + pose[va_BoneIndices.y] * vec4(bulk * va_Vertex1, 1.0) * va_Weights.y
                           + pose[va_BoneIndices.z] * vec4(bulk * va_Vertex2, 1.0) * va_Weights.z;
            newVertex.xyz += rootOffset;
            gl_Position = projectionMatrix * modelViewMatrix * vec4(newVertex.xyz, 1.0);
        }
    `;

    private GLint rootOffsetLoc;

    override string vertexShaderSrc()
    {
        return sacrificeVertexShader;
    }

    this(Owner owner)
    {
        super(owner);
        rootOffsetLoc = glGetUniformLocation(shaderProgram, "rootOffset");
    }

    void setPose(Matrix4x4f[] pose,
        Vector3f rootOffset = Vector3f(0.0f, 0.0f, 0.0f))
    {
        super.setPose(pose);
        glUniform3fv(rootOffsetLoc, 1, rootOffset.arrayof.ptr);
    }
}
