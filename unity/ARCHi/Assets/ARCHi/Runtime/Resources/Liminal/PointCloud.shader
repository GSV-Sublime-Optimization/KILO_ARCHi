Shader "ARCHi/Liminal Baked Point Cloud" {
 Properties { _Opacity("Visibility",Range(0,1))=1 _LightIntensity("Native light intensity",Float)=1 }
 SubShader {
  Tags { "Queue"="Transparent" "RenderType"="Transparent" }
  Blend One OneMinusSrcAlpha
  ZWrite Off
  ZTest LEqual
  Cull Off
  Pass {
   CGPROGRAM
   #pragma target 4.5
   #pragma vertex vert
   #pragma fragment frag
   #include "UnityCG.cginc"
   struct PointSample { float3 position; float3 color; float radius; float emission; };
   StructuredBuffer<PointSample> _FrameA;
   StructuredBuffer<PointSample> _FrameB;
   StructuredBuffer<uint> _Knowledge;
   float4x4 _PointLocalToWorld;
   float _FrameBlend, _Opacity, _Inspection, _Palette, _PointScale, _LightIntensity;
   struct v2f { float4 pos:SV_POSITION; float2 corner:TEXCOORD0; float3 color:TEXCOORD1; float emission:TEXCOORD2; };
   float3 palette(float3 c) {
    if (_Palette < .5) return c;
    float hi=max(c.r,max(c.g,c.b)),lo=min(c.r,min(c.g,c.b));
    if(hi<.0001 || (hi-lo)/hi<.12 || (c.r>c.b*1.2 && c.g>c.b*1.2 && c.g>c.r*.18)) return c;
    float3 tint=_Palette<1.5?float3(.05,1,.72):_Palette<2.5?float3(1,.03,.20):
       _Palette<3.5?float3(.52,.10,1):_Palette<4.5?float3(1,.65,.06):float3(1,1,1);
    return lerp(hi.xxx,tint*hi,saturate((hi-lo)/hi));
   }
   float encodeSRGB(float value) {
    return value<=.0031308 ? 12.92*value : 1.055*pow(value,1.0/2.4)-.055;
   }
   v2f vert(uint vertex:SV_VertexID, uint instance:SV_InstanceID) {
    float2 corners[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    PointSample a=_FrameA[instance],b=_FrameB[instance];
    float3 p=lerp(a.position,b.position,_FrameBlend);
    float radius=max(.00001,lerp(a.radius,b.radius,_FrameBlend));
    float3 world=mul(_PointLocalToWorld,float4(p,1)).xyz;
    float3 view=mul(UNITY_MATRIX_V,float4(world,1)).xyz;
    uint knowledge=_Knowledge[instance];
    float anchor=_Inspection>.5 && knowledge==2?1:0;
    float pixelRadius=(unity_OrthoParams.w>.5?1:max(abs(view.z),.001))/(max(abs(UNITY_MATRIX_P._m11),.001)*_ScreenParams.y);
    float screenRadius=max(radius*_PointScale,pixelRadius);
    screenRadius=lerp(screenRadius,max(screenRadius*2.5,pixelRadius*6),anchor);
    view.xy+=corners[vertex]*screenRadius;
    v2f o;o.pos=mul(UNITY_MATRIX_P,float4(view,1));o.corner=corners[vertex];
    o.color=palette(max(0,lerp(a.color,b.color,_FrameBlend)));
    o.color=lerp(o.color,float3(.9,.65,.16),anchor*.55);
    o.emission=clamp(lerp(a.emission,b.emission,_FrameBlend),0,8);return o;
   }
   float4 frag(v2f i):SV_Target {
    float r2=dot(i.corner,i.corner);clip(1-r2);
    float alpha=saturate(exp(-r2*4)*(1-r2)*_Opacity);
    float3 radiance=min(i.color*i.emission*_LightIntensity,8);
    float3 presentationColor=1-exp(-radiance);
    // Linear Rec.709 -> tone map -> sRGB (Gamma project) -> premultiply -> composite.
    // Encode before premultiplication so translucent edges retain the same color.
    // Linear projects retain linear output for Unity's render-target conversion.
    #if defined(UNITY_COLORSPACE_GAMMA)
    presentationColor=float3(encodeSRGB(presentationColor.r),encodeSRGB(presentationColor.g),encodeSRGB(presentationColor.b));
    #endif
    return float4(presentationColor*alpha,alpha);
   }
   ENDCG
  }
 }
 Fallback Off
}
