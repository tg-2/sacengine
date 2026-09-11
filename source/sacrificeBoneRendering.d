module sacrificeBoneRendering;

import derelict.opengl;

import dagon.core.ownership : Owner;
import dagon.graphics.boneMesh : DagonBoneMesh = BoneMesh;
import dagon.graphics.rc : RenderingContext;

class SacrificeBoneMesh: DagonBoneMesh
{
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
