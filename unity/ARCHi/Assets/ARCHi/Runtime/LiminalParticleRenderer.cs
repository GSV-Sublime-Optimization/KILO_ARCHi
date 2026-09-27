using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Rendering;

namespace ARCHi.Port
{
    [Serializable] public sealed class LiminalKnowledgeBinding { public string nodeID; public uint anchorID; public uint[] particleIDs; }
    [Serializable] public sealed class LiminalPointKnowledge
    {
        public int schemaVersion;
        public string sessionID, originDigest, manifestSHA256, graphDigest;
        public LiminalKnowledgeBinding[] bindings;
    }

    /// <summary>One GPU point presentation reused by room and Arena. Never owns identity, knowledge or gameplay.</summary>
    public sealed class LiminalParticleRenderer : MonoBehaviour
    {
        private static readonly int FrameAID=Shader.PropertyToID("_FrameA"),FrameBID=Shader.PropertyToID("_FrameB"),KnowledgeID=Shader.PropertyToID("_Knowledge"),
            MatrixID=Shader.PropertyToID("_PointLocalToWorld"),BlendID=Shader.PropertyToID("_FrameBlend"),OpacityID=Shader.PropertyToID("_Opacity"),
            InspectionID=Shader.PropertyToID("_Inspection"),PaletteID=Shader.PropertyToID("_Palette"),ScaleID=Shader.PropertyToID("_PointScale"),
            LightIntensityID=Shader.PropertyToID("_LightIntensity"),SeedTextureID=Shader.PropertyToID("_SeedTex"),
            SeedWeightID=Shader.PropertyToID("_SeedWeight"),SeedCenterSizeID=Shader.PropertyToID("_SeedCenterSize");
        public const string SeedStyleRevision="garnet-seed/v1";
        private CancellationTokenSource cancellation;
        private CancellationTokenSource sampleCancellation;
        private Task<LiminalPointAsset> loading;
        private Task<LiminalPointAsset.SamplePair> sampling;
        private LiminalPointAsset asset;
        private LiminalPointAsset.SamplePair pair;
        private NativePointPresentation descriptor;
        private string requestedDigest;
        private Material material;
        private ComputeBuffer firstBuffer,secondBuffer,knowledgeBuffer;
        private Camera roomCamera,renderCamera;
        private Transform contextRoot;
        private Vector3 contextPosition;
        private float contextScale=1,blend,frameAverage=1f/30,qualityAge;
        private int desiredCount=100000,bufferCount;
        private bool externalContext,visible,still=true,reduced,disposed,renderDirty,sampleFailure,rendered;
        private float playhead,lightIntensity=1;
        private Texture2D[] endpointTextures;
        private string endpointColor;
        private Texture2D seedTexture;
        private string seedTextureColor;
        private LiminalPointKnowledge knowledge;
        private string knowledgeDigest;
        private uint[] knowledgeFlags;
        private readonly Dictionary<uint,LiminalKnowledgeBinding> anchors=new Dictionary<uint,LiminalKnowledgeBinding>();
        public RenderTexture Texture {get;private set;}
        private bool BuffersReady => !disposed && asset!=null&&pair!=null&&material!=null&&material.shader.isSupported&&firstBuffer!=null&&secondBuffer!=null;
        public bool Ready => BuffersReady&&rendered;
        public bool Visible => Ready&&visible;
        public bool Inspection {get;private set;}
        public bool CanInspect => Visible&&knowledge!=null&&anchors.Count>0;
        public string ManifestSHA256 => Ready?asset.ManifestSHA256:null;
        public string KnowledgeSHA256 => Ready&&knowledge!=null?knowledgeDigest:null;
        public string GraphDigest => knowledge?.graphDigest;
        public string Status {get;private set;}="Point presentation unavailable.";
        public int PointCount => Ready?bufferCount:0;
        public float RenderedProgress {get;private set;}
        public bool EndpointFallback => pair?.endpointFallback==true;
        public Texture2D EndpointTexture {
            get {
                if(Ready||!visible||endpointTextures==null)return null;
                int endpoint=NearestEndpoint(playhead);
                if(endpoint==2){EnsureSeedTexture();if(seedTexture!=null)return seedTexture;}
                return endpointTextures[endpoint];
            }
        }
        public event Action<string,uint> Selected;

        public void Initialize(Transform owner)
        {
            if(roomCamera!=null)return;
            transform.SetParent(owner,false);
            var cameraObject=new GameObject("Liminal transparent point camera");cameraObject.transform.SetParent(transform,false);
            roomCamera=cameraObject.AddComponent<Camera>();roomCamera.enabled=false;roomCamera.cullingMask=1<<28;
            roomCamera.clearFlags=CameraClearFlags.SolidColor;roomCamera.backgroundColor=Color.clear;
            roomCamera.allowHDR=true;roomCamera.allowMSAA=false;roomCamera.orthographic=true;roomCamera.orthographicSize=1;
            roomCamera.nearClipPlane=.1f;roomCamera.farClipPlane=10;roomCamera.transform.localPosition=new Vector3(0,0,-4);
            roomCamera.transform.localRotation=Quaternion.identity;
            Texture=new RenderTexture(768,768,24,RenderTextureFormat.ARGBHalf){name="Liminal v008 transparent points",antiAliasing=1};Texture.Create();
            roomCamera.targetTexture=Texture;
            cameraObject.AddComponent<LiminalPointComposite>();
            UseRoom();
        }
        public void UseRoom()
        {
            externalContext=false;renderCamera=roomCamera;contextRoot=transform;contextPosition=Vector3.zero;contextScale=1;Inspection=false;renderDirty=true;
        }
        public void UseArena(Camera camera,Transform root,Vector3 position,float scale)
        {
            externalContext=true;renderCamera=camera;contextRoot=root;contextPosition=position;contextScale=scale;Inspection=false;renderDirty=true;
        }
        public void Configure(NativePresentationSnapshot snapshot,bool freeze)
        {
            var next=snapshot?.pointPresentation;
            bool eligible=next!=null && next.IsValid(snapshot);
            if(descriptor?.progress!=next?.progress)sampleFailure=false;
            descriptor=eligible?next:null;
            lightIntensity=LightIntensity(snapshot?.lightMode);
            visible=eligible&&snapshot.active&&snapshot.visible&&next.visible;
            reduced=eligible&&(snapshot.reduceMotion||snapshot.quiet||next.motion=="reduced");
            still=freeze||!eligible||reduced;
            if(!visible)Inspection=false;
            if(!eligible||!visible){RetireAsset();return;}
            if(requestedDigest!=next.manifestSHA256){
                RetireAsset();requestedDigest=next.manifestSHA256;cancellation=new CancellationTokenSource();
                playhead=next.progress;
                string root=Path.Combine(Application.streamingAssetsPath,"LiminalV008"),digest=requestedDigest;
                var token=cancellation.Token;
                loading=Task.Run(()=>LiminalPointAsset.Load(root,digest,token),token);
                Status="Checking the authored v008 point package…";
            }
            if(reduced)playhead=EndpointProgress(NearestEndpoint(next.progress));
            if(still)CancelSampling();
            if(asset?.EndpointPNGs!=null&&endpointColor!=descriptor.color)LoadEndpointTextures();
            renderDirty=true;
        }
        public void Suspend(){visible=false;still=true;Inspection=false;RetireAsset();renderDirty=true;}
        public void Freeze(bool value){still=value||reduced;if(still){CancelSampling();if(Ready)playhead=RenderedProgress;}renderDirty=true;}
        public bool SetInspection(bool value)
        {
            Inspection=value&&CanInspect;if(Inspection){CancelSampling();if(Ready)playhead=RenderedProgress;}renderDirty=true;return Inspection;
        }
        public bool ApplyKnowledge(LiminalPointKnowledge projection,string digest,NativePresentationSnapshot snapshot)
        {
            ClearKnowledge();
            if(asset==null||projection==null||snapshot==null||projection.schemaVersion!=1||projection.sessionID!=snapshot.sessionID
                ||projection.originDigest!=snapshot.originDigest||projection.manifestSHA256!=asset.ManifestSHA256
                ||projection.manifestSHA256!=snapshot.pointPresentation?.manifestSHA256||!LiminalPointAsset.IsDigest(projection.graphDigest)
                ||!LiminalPointAsset.IsDigest(digest)||digest!=snapshot.pointKnowledgeSHA256||projection.bindings==null||projection.bindings.Length>220)return false;
            var used=new HashSet<uint>();var nodes=new HashSet<string>(StringComparer.Ordinal);
            var accepted=new Dictionary<uint,LiminalKnowledgeBinding>();
            foreach(var binding in projection.bindings){
                if(binding==null||string.IsNullOrWhiteSpace(binding.nodeID)||System.Text.Encoding.UTF8.GetByteCount(binding.nodeID)>256
                    ||Array.Exists(binding.nodeID.ToCharArray(),char.IsControl)||!nodes.Add(binding.nodeID)||binding.particleIDs==null
                    ||binding.particleIDs.Length<1||binding.particleIDs.Length>32||!asset.TryRank(binding.anchorID,out int anchorRank)
                    ||anchorRank>=LiminalPointAsset.MinimumCount)return false;
                bool hasAnchor=false;
                foreach(uint id in binding.particleIDs){if(!asset.TryRank(id,out int rank)||!used.Add(id))return false;hasAnchor|=id==binding.anchorID;}
                if(!hasAnchor||accepted.ContainsKey(binding.anchorID))return false;
                accepted.Add(binding.anchorID,binding);
            }
            knowledge=projection;knowledgeDigest=digest;
            foreach(var item in accepted)anchors.Add(item.Key,item.Value);
            UpdateKnowledgeBuffer();renderDirty=true;return true;
        }
        public void ClearKnowledge()
        {
            knowledge=null;knowledgeDigest=null;anchors.Clear();Inspection=false;
            if(knowledgeFlags!=null){Array.Clear(knowledgeFlags,0,knowledgeFlags.Length);knowledgeBuffer?.SetData(knowledgeFlags);}
            renderDirty=true;
        }
        private void UpdateKnowledgeBuffer()
        {
            if(bufferCount==0||knowledgeBuffer==null)return;
            if(knowledgeFlags==null||knowledgeFlags.Length!=bufferCount)knowledgeFlags=new uint[bufferCount];else Array.Clear(knowledgeFlags,0,knowledgeFlags.Length);
            if(knowledge!=null)foreach(var binding in knowledge.bindings)foreach(uint id in binding.particleIDs)
                if(asset.TryRank(id,out int index)&&index<bufferCount)knowledgeFlags[index]=id==binding.anchorID?2u:1u;
            knowledgeBuffer.SetData(knowledgeFlags);
        }
        public bool Pick(Vector2 viewport)
        {
            if(!Inspection||!CanInspect||renderCamera==null||viewport.x<0||viewport.y<0||viewport.x>1||viewport.y>1)return false;
            float best=.025f*.025f;LiminalKnowledgeBinding selected=null;uint point=0;
            var matrix=PointMatrix();
            foreach(var binding in anchors.Values){
                if(!asset.TryRank(binding.anchorID,out int rank)||rank>=bufferCount)continue;
                var local=Vector3.Lerp(pair.first[rank].position,pair.second[rank].position,blend);
                var projected=renderCamera.WorldToViewportPoint(matrix.MultiplyPoint3x4(local));
                if(projected.z<=0||projected.x<0||projected.y<0||projected.x>1||projected.y>1)continue;
                float distance=(new Vector2(projected.x,projected.y)-viewport).sqrMagnitude;
                if(distance<best){best=distance;selected=binding;point=binding.anchorID;}
            }
            if(selected==null)return false;
            Selected?.Invoke(selected.nodeID,point);return true;
        }
        public bool HasBinding(string nodeID,uint id)=>knowledge!=null&&anchors.TryGetValue(id,out var binding)&&binding.nodeID==nodeID;

        private void Update()
        {
            if(disposed)return;
            if(loading!=null&&loading.IsCompleted){
                var finished=loading;loading=null;
                try {asset=finished.GetAwaiter().GetResult();LoadEndpointTextures();EnsureMaterial();Status="Loading authored point samples…";}
                catch(Exception error){Status="Verified endpoint or authored Seed fallback · "+Short(error.Message);}
            }
            if(sampling!=null&&sampling.IsCompleted){
                var finished=sampling;sampling=null;
                sampleCancellation?.Dispose();sampleCancellation=null;
                try{Publish(finished.GetAwaiter().GetResult());}
                catch(Exception error){
                    if(asset!=null&&descriptor!=null){sampleFailure=true;Publish(asset.Endpoint(playhead,desiredCount));Status="Verified endpoint held · "+Short(error.Message);}
                    else Status="Authored Seed fallback · point samples unavailable.";
                }
            }
            if(asset==null||descriptor==null||material==null||!visible)return;
            // A capped 30 fps player lowers LOD after sustained missed frames and
            // raises it only after a stable interval. It never fabricates points.
            frameAverage=Mathf.Lerp(frameAverage,Mathf.Min(Time.unscaledDeltaTime,.2f),.035f);qualityAge+=Time.unscaledDeltaTime;
            if(qualityAge>2&&frameAverage>.041f&&desiredCount>50000){desiredCount=desiredCount==200000?100000:50000;qualityAge=0;}
            else if(qualityAge>8&&frameAverage<.0355f&&desiredCount<200000){desiredCount=desiredCount==50000?100000:200000;qualityAge=0;}
            if(!still&&!Inspection&&Ready&&sampling==null&&!sampleFailure){
                float next=Mathf.MoveTowards(playhead,descriptor.progress,Mathf.Min(Time.unscaledDeltaTime,.1f)*24f/119f);
                playhead=next;
            }
            int first=LiminalPointAsset.FrameForProgress(playhead);
            if(reduced&&sampling==null&&(pair==null||!pair.endpointFallback||pair.frame!=first||pair.count!=desiredCount))Publish(asset.Endpoint(playhead,desiredCount));
            if(!reduced&&!sampleFailure&&sampling==null&&(pair==null||pair.endpointFallback||pair.frame!=first||pair.count!=desiredCount)){
                var current=asset;int count=desiredCount;
                sampleCancellation=CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);var token=sampleCancellation.Token;
                sampling=Task.Run(()=>current.ReadPair(first,count,token),token);
            }
            if(BuffersReady){
                // The source rounds $F half-up. Blending adjacent samples would invent motion.
                blend=0;
                RenderedProgress=pair.endpointFallback?pair.endpointProgress:(pair.frame-1)/119f;
                if(!externalContext&&renderDirty){roomCamera.Render();renderDirty=false;}
            }
        }
        private void EnsureMaterial()
        {
            if(material!=null)return;
            var shader=Resources.Load<Shader>("Liminal/PointCloud");
            if(shader==null||!shader.isSupported||SystemInfo.graphicsShaderLevel<45)throw new InvalidDataException("Point shader unavailable on this graphics device.");
            material=new Material(shader){name="Liminal v008 premultiplied points",enableInstancing=true};
        }
        private void EnsureSeedTexture()
        {
            string color=descriptor?.color;
            if(color==null||seedTextureColor==color)return;
            seedTextureColor=color;seedTexture=null;
            // Reuse the bundled, build-checked Hampton artwork and palette owner.
            // A missing decoration leaves the authenticated source particles intact.
            try{seedTexture=SeedAppearanceRendering.Texture("hamptonLiminal",color=="original"?"garnet":color);}
            catch(Exception){seedTexture=null;}
        }
        private void LoadEndpointTextures()
        {
            if(asset.EndpointPNGs==null)return;
            var decoded=new Texture2D[3];
            try{
                for(int i=0;i<3;i++){
                    decoded[i]=new Texture2D(2,2,TextureFormat.RGBA32,false,false){name="Verified Liminal "+i,wrapMode=TextureWrapMode.Clamp};
                    if(!ImageConversion.LoadImage(decoded[i],asset.EndpointPNGs[i],false)||decoded[i].width!=512||decoded[i].height!=512)
                        throw new InvalidDataException("Verified endpoint image did not decode as 512 by 512.");
                    if(descriptor.color!="original"){
                        var pixels=decoded[i].GetPixels32();for(int p=0;p<pixels.Length;p++)pixels[p]=SeedAppearanceRendering.Recolor(pixels[p],descriptor.color,true);
                        decoded[i].SetPixels32(pixels);
                    }
                    decoded[i].Apply(false,true);
                }
                if(endpointTextures!=null)foreach(var image in endpointTextures)if(image!=null)Destroy(image);
                endpointTextures=decoded;endpointColor=descriptor.color;
            }catch{foreach(var image in decoded)if(image!=null)Destroy(image);throw;}
        }
        private static int NearestEndpoint(float progress){float f=1+progress*119;int p=Mathf.Abs(f-24)<=Mathf.Abs(f-66)?0:1;return Mathf.Abs(f-108)<Mathf.Abs(f-(p==0?24:66))?2:p;}
        private static float EndpointProgress(int pose)=>(pose==0?23:pose==1?65:107)/119f;
        private void Publish(LiminalPointAsset.SamplePair next)
        {
            if(descriptor==null||asset==null)return;
            if(bufferCount!=next.count){
                ReleaseBuffers();bufferCount=next.count;
                firstBuffer=new ComputeBuffer(bufferCount,32);secondBuffer=new ComputeBuffer(bufferCount,32);knowledgeBuffer=new ComputeBuffer(bufferCount,4);
                knowledgeFlags=new uint[bufferCount];
            }
            firstBuffer.SetData(next.first);secondBuffer.SetData(next.second);pair=next;UpdateKnowledgeBuffer();
            Status=next.endpointFallback?(reduced?"Reduced motion · verified v008 endpoint.":"Verified v008 endpoint · motion unavailable."):"Authored v008 samples · "+bufferCount.ToString("N0")+" points";
            renderDirty=true;
        }
        private Matrix4x4 PointMatrix()
        {
            var parent=contextRoot==null?Matrix4x4.identity:contextRoot.localToWorldMatrix;
            return parent*Matrix4x4.TRS(contextPosition,Quaternion.identity,Vector3.one*contextScale)
                *Matrix4x4.Scale(Vector3.one*StyledFitScale())*Matrix4x4.Translate(-StyledCenter());
        }
        // Presentation framing follows the loaded source sample, never a requested
        // playhead that may be ahead of disk reads. Art IDs and samples do not change.
        private float SeedWeight(){float t=Mathf.Clamp01(((pair?.frame??1)-90)/18f);return t*t*(3-2*t);}
        private Vector3 StyledCenter()=>Vector3.Lerp(asset.Center,new Vector3(0,1.15f,asset.Center.z),SeedWeight());
        private float StyledFitScale()=>2/Mathf.Lerp(2/asset.FitScale,1.90f,SeedWeight());
        private void OnRenderObject()
        {
            if(!BuffersReady||!visible||Camera.current!=renderCamera||contextRoot==null)return;
            EnsureSeedTexture();
            float seedWeight=Inspection||seedTexture==null?0:SeedWeight();
            if(seedWeight>0){
                var center=PointMatrix().MultiplyPoint3x4(new Vector3(0,1.15f,asset.Center.z));
                material.SetTexture(SeedTextureID,seedTexture);material.SetFloat(SeedWeightID,seedWeight);
                material.SetVector(SeedCenterSizeID,new Vector4(center.x,center.y,center.z,.95f*StyledFitScale()*contextScale*Mathf.Abs(contextRoot.lossyScale.x)));
                // Check the decoration pass before attenuating particles. It is
                // optional presentation, never a reason to hide the source form.
                if(material.passCount<2||!material.SetPass(1))seedWeight=0;
            }
            material.SetBuffer(FrameAID,firstBuffer);material.SetBuffer(FrameBID,secondBuffer);material.SetBuffer(KnowledgeID,knowledgeBuffer);
            material.SetMatrix(MatrixID,PointMatrix());material.SetFloat(BlendID,blend);material.SetFloat(OpacityID,1-.85f*seedWeight);
            material.SetFloat(InspectionID,Inspection?1:0);material.SetFloat(ScaleID,StyledFitScale()*contextScale*contextRoot.lossyScale.x);
            material.SetFloat(PaletteID,Palette(descriptor.color));
            material.SetFloat(LightIntensityID,lightIntensity);
            if(!material.SetPass(0)){Status="Verified endpoint or authored Seed fallback · point shader pass unavailable.";return;}
            Graphics.DrawProceduralNow(MeshTopology.Triangles,6,bufferCount);rendered=true;
            // Decorative orbit lines are never selectable knowledge. Inspection
            // retains identical framing and draws the full source particles only.
            if(seedWeight>0&&material.SetPass(1))Graphics.DrawProceduralNow(MeshTopology.Triangles,6,1);
        }
        private static float Palette(string color)=>color=="aqua"?1:color=="garnet"?2:color=="violet"?3:color=="gold"?4:color=="pearl"?5:0;
        // Matches native 1 + KinLightEmission.intensity(mode:, phase: 0).
        private static float LightIntensity(string mode)=>mode=="core"?1.1892f:mode=="orbit"?1.258f:mode=="focus"?1.172f:
            mode=="pulse"?1.3268f:mode=="delight"?1.2924f:mode=="hold"?1.18f:1;
        private static string Short(string message)=>string.IsNullOrEmpty(message)?"unavailable":message.Substring(0,Math.Min(120,message.Length));
        private void ReleaseBuffers(){firstBuffer?.Release();secondBuffer?.Release();knowledgeBuffer?.Release();firstBuffer=secondBuffer=knowledgeBuffer=null;bufferCount=0;knowledgeFlags=null;rendered=false;}
        private void RetireAsset()
        {
            CancelSampling();
            cancellation?.Cancel();cancellation?.Dispose();cancellation=null;
            // Workers hold immutable data only. Retired completions are observed
            // but have no route back to the current presentation or its buffers.
            if(loading!=null)Observe(loading);if(sampling!=null)Observe(sampling);
            loading=null;sampling=null;asset=null;pair=null;requestedDigest=null;ClearKnowledge();ReleaseBuffers();
            seedTexture=null;seedTextureColor=null; // Cached textures belong to SeedAppearanceRendering.
            if(endpointTextures!=null){foreach(var image in endpointTextures)if(image!=null)Destroy(image);endpointTextures=null;}
            Status="Authored Seed fallback · no qualified point package.";
        }
        private void CancelSampling(){
            sampleCancellation?.Cancel();sampleCancellation?.Dispose();sampleCancellation=null;
            if(sampling!=null)Observe(sampling);sampling=null;
        }
        private static void Observe(Task task){task.ContinueWith(t=>{var ignored=t.Exception;},TaskContinuationOptions.OnlyOnFaulted);}
        private void OnDisable(){visible=false;Inspection=false;}
        private void OnDestroy()
        {
            disposed=true;RetireAsset();if(material!=null)Destroy(material);
            if(roomCamera!=null)roomCamera.targetTexture=null;
            if(Texture!=null){Texture.Release();Destroy(Texture);}
        }
    }

    /// <summary>UI Toolkit Images consume straight alpha; point accumulation stays premultiplied.</summary>
    public sealed class LiminalPointComposite : MonoBehaviour
    {
        private Material material;
        private void OnEnable(){var shader=Resources.Load<Shader>("Liminal/PointComposite");if(shader!=null&&shader.isSupported)material=new Material(shader){hideFlags=HideFlags.HideAndDontSave};}
        private void OnRenderImage(RenderTexture source,RenderTexture destination){if(material!=null)Graphics.Blit(source,destination,material);else Graphics.Blit(source,destination);}
        private void OnDisable(){if(material!=null)Destroy(material);material=null;}
    }
}
