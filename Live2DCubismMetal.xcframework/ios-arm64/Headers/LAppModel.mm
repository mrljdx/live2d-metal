/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#import "LAppModel.h"
#import <Foundation/Foundation.h>
#import <fstream>
#import <vector>
#import "LAppDefine.h"
#import "LAppPal.h"
#import "LAppTextureManager.h"
#import "AppDelegate.h"
#import "L2DCubism.h"
#import "Live2DCallbackBridge.h"
#import <CubismDefaultParameterId.hpp>
#import <CubismModelSettingJson.hpp>
#import <Id/CubismIdManager.hpp>
#import <Motion/CubismMotion.hpp>
#import <Motion/CubismMotionQueueEntry.hpp>
#import <Physics/CubismPhysics.hpp>
#import <Rendering/Metal/CubismRenderer_Metal.hpp>
#import <Utils/CubismString.hpp>

using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Framework::DefaultParameterId;
using namespace LAppDefine;

namespace {
    csmByte* CreateBuffer(const csmChar* path, csmSizeInt* size)
    {
        if (DebugLogEnable)
        {
            LAppPal::PrintLogLn("[APP]create buffer: %s ", path);
        }
        return LAppPal::LoadFileAsBytes(path,size);
    }

    void DeleteBuffer(csmByte* buffer, const csmChar* path = "")
    {
        if (DebugLogEnable)
        {
            LAppPal::PrintLogLn("[APP]delete buffer: %s", path);
        }
        LAppPal::ReleaseBytes(buffer);
    }
}

LAppModel::LAppModel()
: CubismUserModel()
, _modelSetting(NULL)
, _userTimeSeconds(0.0f)
, _lipSyncValue(0.0f)
, _lipSyncSensitivity(3.0f) // 默认灵敏度1.5倍
{
    if (MocConsistencyValidationEnable)
    {
        _mocConsistency = true;
    }

    if (DebugLogEnable)
    {
        _debugMode = true;
    }

    _idParamAngleX = CubismFramework::GetIdManager()->GetId(ParamAngleX);
    _idParamAngleY = CubismFramework::GetIdManager()->GetId(ParamAngleY);
    _idParamAngleZ = CubismFramework::GetIdManager()->GetId(ParamAngleZ);
    _idParamBodyAngleX = CubismFramework::GetIdManager()->GetId(ParamBodyAngleX);
    _idParamEyeBallX = CubismFramework::GetIdManager()->GetId(ParamEyeBallX);
    _idParamEyeBallY = CubismFramework::GetIdManager()->GetId(ParamEyeBallY);
}

LAppModel::~LAppModel()
{
    Release();
}

void LAppModel::LoadAssets(const csmChar* dir, const csmChar* fileName)
{
    _modelHomeDir = dir;

    if (_debugMode)
    {
        LAppPal::PrintLogLn("[APP]load model setting: %s", fileName);
    }

    csmSizeInt size;
    const csmString path = csmString(dir) + fileName;

    csmByte* buffer = CreateBuffer(path.GetRawString(), &size);
    ICubismModelSetting* setting = new CubismModelSettingJson(buffer, size);
    DeleteBuffer(buffer, path.GetRawString());

    SetupModel(setting);

    if (_model == NULL)
    {
        LAppPal::PrintLogLn("[APP]Failed to LoadAssets().");
        return;
    }

    CreateRenderer();

    SetupTextures();

    // 新增：传递模型信息到iOS层
    //  已彻底修复字符串内存生命周期问题。主要改进：
    //
    //  1. 使用静态字符数组：采用 static char buffer[] 确保内存持久化
    //  2. 安全的字符串拷贝：使用 strncpy 和 snprintf 进行安全字符串操作
    //  3. 避免内存悬挂：不再使用可能失效的临时对象指针
    Live2DCallbackBridge* callbackBridge = [Live2DCallbackBridge sharedInstance];
    if (callbackBridge) {
        static char gBuffer[256];
        // 2-1 模型目录
        csmString modelDirCsm = _modelHomeDir;               // 先转成 csmString
        const csmChar* modelDirPtr = modelDirCsm.GetRawString();
        strncpy(gBuffer, modelDirPtr, sizeof(gBuffer) - 1);
        gBuffer[sizeof(gBuffer) - 1] = '\0';

        // 提取模型目录名（去除路径前缀和末尾斜杠）
        std::string modelDirStr(modelDirPtr);
        size_t lastSlash = modelDirStr.find_last_of("/", modelDirStr.length() - 2);
        std::string modelName = (lastSlash != std::string::npos) ? 
            modelDirStr.substr(lastSlash + 1) : modelDirStr;
        if (!modelName.empty() && modelName.back() == '/') {
            modelName.pop_back();
        }
        
        // 使用字符数组确保内存持久化
        static char modelNameBuffer[256];
        strncpy(modelNameBuffer, modelName.c_str(), sizeof(modelNameBuffer) - 1);
        modelNameBuffer[sizeof(modelNameBuffer) - 1] = '\0';

        // 立即调用model_name回调，避免静态缓冲区覆盖
        {
            [callbackBridge onResourceInfo:modelNameBuffer
                              resourceType:"model_name"
                              resourcePath:modelNameBuffer];
        }

        // 2-2 JSON 文件
        {
            static char jsonPathBuffer[512];
            snprintf(jsonPathBuffer, sizeof(jsonPathBuffer), "%s/%s", modelName.c_str(), fileName);
            [callbackBridge onResourceInfo:modelNameBuffer
                              resourceType:"json_file"
                              resourcePath:jsonPathBuffer];
        }

        // 2. 纹理列表
        for (csmInt32 i = 0; i < _modelSetting->GetTextureCount(); i++) {
            static char texturePathBuffer[512];
            const csmChar* texFileName = _modelSetting->GetTextureFileName(i);
            snprintf(texturePathBuffer, sizeof(texturePathBuffer), "%s/%s", modelName.c_str(), texFileName);
            [callbackBridge onResourceInfo:modelNameBuffer
                              resourceType:"texture"
                              resourcePath:texturePathBuffer];
        }

    }

}


void LAppModel::SetupModel(ICubismModelSetting* setting)
{
    _updating = true;
    _initialized = false;

    _modelSetting = setting;

    csmByte* buffer;
    csmSizeInt size;

    //Cubism Model
    if (strcmp(_modelSetting->GetModelFileName(), "") != 0)
    {
        csmString path = _modelSetting->GetModelFileName();
        path = _modelHomeDir + path;

        if (_debugMode)
        {
            LAppPal::PrintLogLn("[APP]create model: %s", setting->GetModelFileName());
        }

        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadModel(buffer, size, _mocConsistency);
        DeleteBuffer(buffer, path.GetRawString());
    }

    //Expression
    if (_modelSetting->GetExpressionCount() > 0)
    {
        const csmInt32 count = _modelSetting->GetExpressionCount();
        for (csmInt32 i = 0; i < count; i++)
        {
            csmString name = _modelSetting->GetExpressionName(i);
            csmString path = _modelSetting->GetExpressionFileName(i);
            path = _modelHomeDir + path;

            buffer = CreateBuffer(path.GetRawString(), &size);
            ACubismMotion* motion = LoadExpression(buffer, size, name.GetRawString());

            if (motion)
            {
                if (_expressions[name] != NULL)
                {
                    ACubismMotion::Delete(_expressions[name]);
                    _expressions[name] = NULL;
                }
                _expressions[name] = motion;
            }

            DeleteBuffer(buffer, path.GetRawString());
        }
    }

    //Physics
    if (strcmp(_modelSetting->GetPhysicsFileName(), "") != 0)
    {
        csmString path = _modelSetting->GetPhysicsFileName();
        path = _modelHomeDir + path;

        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadPhysics(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }

    //Pose
    if (strcmp(_modelSetting->GetPoseFileName(), "") != 0)
    {
        csmString path = _modelSetting->GetPoseFileName();
        path = _modelHomeDir + path;

        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadPose(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }

    //EyeBlink
    if (_modelSetting->GetEyeBlinkParameterCount() > 0)
    {
        _eyeBlink = CubismEyeBlink::Create(_modelSetting);
    }

    //Breath
    {
        _breath = CubismBreath::Create();

        csmVector<CubismBreath::BreathParameterData> breathParameters;

        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleX, 0.0f, 15.0f, 6.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleY, 0.0f, 8.0f, 3.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleZ, 0.0f, 10.0f, 5.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamBodyAngleX, 0.0f, 4.0f, 15.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(CubismFramework::GetIdManager()->GetId(ParamBreath), 0.5f, 0.5f, 3.2345f, 0.5f));

        _breath->SetParameters(breathParameters);
    }

    //UserData
    if (strcmp(_modelSetting->GetUserDataFile(), "") != 0)
    {
        csmString path = _modelSetting->GetUserDataFile();
        path = _modelHomeDir + path;
        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadUserData(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }

    // EyeBlinkIds
    {
        csmInt32 eyeBlinkIdCount = _modelSetting->GetEyeBlinkParameterCount();
        for (csmInt32 i = 0; i < eyeBlinkIdCount; ++i)
        {
            _eyeBlinkIds.PushBack(_modelSetting->GetEyeBlinkParameterId(i));
        }
    }

    // LipSyncIds
    {
        csmInt32 lipSyncIdCount = _modelSetting->GetLipSyncParameterCount();
        for (csmInt32 i = 0; i < lipSyncIdCount; ++i)
        {
            _lipSyncIds.PushBack(_modelSetting->GetLipSyncParameterId(i));
        }
    }

    if (_modelSetting == NULL || _modelMatrix == NULL)
    {
        LAppPal::PrintLogLn("Failed to SetupModel().");
        return;
    }

    //Layout
    csmMap<csmString, csmFloat32> layout;
    _modelSetting->GetLayoutMap(layout);
    _modelMatrix->SetupFromLayout(layout);

    _model->SaveParameters();

    for (csmInt32 i = 0; i < _modelSetting->GetMotionGroupCount(); i++)
    {
        const csmChar* group = _modelSetting->GetMotionGroupName(i);
        PreloadMotionGroup(group);
    }

    _motionManager->StopAllMotions();

    _updating = false;
    _initialized = true;
}

void LAppModel::PreloadMotionGroup(const csmChar* group)
{
    const csmInt32 count = _modelSetting->GetMotionCount(group);

    for (csmInt32 i = 0; i < count; i++)
    {
        //ex) idle_0
        csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, i);
        csmString path = _modelSetting->GetMotionFileName(group, i);
        path = _modelHomeDir + path;

        if (_debugMode)
        {
            LAppPal::PrintLogLn("[APP]load motion: %s => [%s_%d] ", path.GetRawString(), group, i);
        }

        csmByte* buffer;
        csmSizeInt size;
        buffer = CreateBuffer(path.GetRawString(), &size);
        CubismMotion* tmpMotion = static_cast<CubismMotion*>(LoadMotion(buffer, size, name.GetRawString(), NULL, NULL, _modelSetting, group, i));

        if (tmpMotion)
        {
            tmpMotion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);

            if (_motions[name] != NULL)
            {
                ACubismMotion::Delete(_motions[name]);
            }
            _motions[name] = tmpMotion;
        }

        DeleteBuffer(buffer, path.GetRawString());
    }
}

void LAppModel::ReleaseMotionGroup(const csmChar* group) const
{
    const csmInt32 count = _modelSetting->GetMotionCount(group);
    for (csmInt32 i = 0; i < count; i++)
    {
        csmString voice = _modelSetting->GetMotionSoundFileName(group, i);
        if (strcmp(voice.GetRawString(), "") != 0)
        {
            csmString path = voice;
            path = _modelHomeDir + path;
        }
    }
}

/**
* @brief すべてのモーションデータの解放
*
* すべてのモーションデータを解放する。
*/
void LAppModel::ReleaseMotions()
{
    for (csmMap<csmString, ACubismMotion*>::const_iterator iter = _motions.Begin(); iter != _motions.End(); ++iter)
    {
        ACubismMotion::Delete(iter->Second);
    }

    _motions.Clear();
}

/**
* @brief すべての表情データの解放
*
* すべての表情データを解放する。
*/
void LAppModel::ReleaseExpressions()
{
    for (csmMap<csmString, ACubismMotion*>::const_iterator iter = _expressions.Begin(); iter != _expressions.End(); ++iter)
    {
        ACubismMotion::Delete(iter->Second);
    }

    _expressions.Clear();
}

void LAppModel::Update()
{
    const csmFloat32 deltaTimeSeconds = LAppPal::GetDeltaTime();
    _userTimeSeconds += deltaTimeSeconds;

    _dragManager->Update(deltaTimeSeconds);
    _dragX = _dragManager->GetX();
    _dragY = _dragManager->GetY();

    // モーションによるパラメータ更新の有無
    csmBool motionUpdated = false;

    //-----------------------------------------------------------------
    _model->LoadParameters(); // 前回セーブされた状態をロード
    if (_motionManager->IsFinished())
    {
        // モーションの再生がない場合、待機モーションの中からランダムで再生する
        StartRandomMotion(MotionGroupIdle, PriorityIdle);
    }
    else
    {
        motionUpdated = _motionManager->UpdateMotion(_model, deltaTimeSeconds); // モーションを更新
    }
    _model->SaveParameters(); // 状態を保存
    //-----------------------------------------------------------------

    // 不透明度
    _opacity = _model->GetModelOpacity();

    // まばたき
    if (!motionUpdated)
    {
        if (_eyeBlink != NULL)
        {
            // メインモーションの更新がないとき
            _eyeBlink->UpdateParameters(_model, deltaTimeSeconds); // 目パチ
        }
    }

    if (_expressionManager != NULL)
    {
        _expressionManager->UpdateMotion(_model, deltaTimeSeconds); // 表情でパラメータ更新（相対変化）
    }

    //ドラッグによる変化
    //ドラッグによる顔の向きの調整
    _model->AddParameterValue(_idParamAngleX, _dragX * 30); // -30から30の値を加える
    _model->AddParameterValue(_idParamAngleY, _dragY * 30);
    _model->AddParameterValue(_idParamAngleZ, _dragX * _dragY * -30);

    //ドラッグによる体の向きの調整
    _model->AddParameterValue(_idParamBodyAngleX, _dragX * 10); // -10から10の値を加える

    //ドラッグによる目の向きの調整
    _model->AddParameterValue(_idParamEyeBallX, _dragX); // -1から1の値を加える
    _model->AddParameterValue(_idParamEyeBallY, _dragY);

    // 呼吸など
    if (_breath != NULL)
    {
        _breath->UpdateParameters(_model, deltaTimeSeconds);
    }

    // 物理演算の設定
    if (_physics != NULL)
    {
        _physics->Evaluate(_model, deltaTimeSeconds);
    }

    // リップシンクの設定
    if (_lipSync)
    {
        // value从外部获取，不再固定为0
        // 使用当前设置的lipSync值
        csmFloat32 value = _lipSyncValue;

        // 添加灵敏度调节
        value = value * _lipSyncSensitivity;
        if (value > 1.0f) value = 1.0f;
        if (value < 0.0f) value = 0.0f;

        for (csmUint32 i = 0; i < _lipSyncIds.GetSize(); ++i)
        {
            _model->AddParameterValue(_lipSyncIds[i], value, 0.8f);
        }
    }

    // ポーズの設定
    if (_pose != NULL)
    {
        _pose->UpdateParameters(_model, deltaTimeSeconds);
    }

    _model->Update();

}

CubismMotionQueueEntryHandle LAppModel::StartMotion(const csmChar* group, csmInt32 no, csmInt32 priority, ACubismMotion::FinishedMotionCallback onFinishedMotionHandler, ACubismMotion::BeganMotionCallback onBeganMotionHandler)
{
    if (priority == PriorityForce)
    {
        _motionManager->SetReservePriority(priority);
    }
    else if (!_motionManager->ReserveMotion(priority))
    {
        if (_debugMode)
        {
            const csmString fileName = _modelSetting->GetMotionFileName(group, no);
            csmString path = fileName;
            path = _modelHomeDir + path;
            LAppPal::PrintLogLn("[APP]can't start motion: %s", path.GetRawString());
        }
        return InvalidMotionQueueEntryHandleValue;
    }

    const csmString fileName = _modelSetting->GetMotionFileName(group, no);

    //ex) idle_0
    csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, no);
    CubismMotion* motion = static_cast<CubismMotion*>(_motions[name.GetRawString()]);
    csmBool autoDelete = false;

    if (motion == NULL)
    {
        csmString path = fileName;
        path = _modelHomeDir + path;

        csmByte* buffer;
        csmSizeInt size;
        buffer = CreateBuffer(path.GetRawString(), &size);
        motion = static_cast<CubismMotion*>(LoadMotion(buffer, size, NULL, onFinishedMotionHandler, NULL, _modelSetting, group, no));

        if (motion)
        {
            motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
            autoDelete = true; // 終了時にメモリから削除
        }

        DeleteBuffer(buffer, path.GetRawString());
    }
    else
    {
        motion->SetBeganMotionHandler(onBeganMotionHandler);
        motion->SetFinishedMotionHandler(onFinishedMotionHandler);
    }

    //voice
    csmString voice = _modelSetting->GetMotionSoundFileName(group, no);
    if (strcmp(voice.GetRawString(), "") != 0)
    {
        csmString path = voice;
        path = _modelHomeDir + path;
    }

    if (_debugMode)
    {
        LAppPal::PrintLogLn("[APP]start motion: [%s_%d]", group, no);
    }
    return  _motionManager->StartMotionPriority(motion, autoDelete, priority);
}

CubismMotionQueueEntryHandle LAppModel::StartRandomMotion(const csmChar* group, csmInt32 priority, ACubismMotion::FinishedMotionCallback onFinishedMotionHandler, ACubismMotion::BeganMotionCallback onBeganMotionHandler)
{
    if (_modelSetting->GetMotionCount(group) == 0)
    {
        return InvalidMotionQueueEntryHandleValue;
    }

    csmInt32 no = rand() % _modelSetting->GetMotionCount(group);

    return StartMotion(group, no, priority, onFinishedMotionHandler, onBeganMotionHandler);
}

void LAppModel::DoDraw()
{
    if (_model == NULL)
    {
        return;
    }

    GetRenderer<Rendering::CubismRenderer_Metal>()->DrawModel();
}

void LAppModel::Draw(CubismMatrix44& matrix)
{
    if (_model == NULL)
    {
        return;
    }

    matrix.MultiplyByMatrix(_modelMatrix);

    GetRenderer<Rendering::CubismRenderer_Metal>()->SetMvpMatrix(&matrix);

    DoDraw();
}

csmBool LAppModel::HitTest(const csmChar* hitAreaName, csmFloat32 x, csmFloat32 y)
{
    // 透明時は当たり判定なし。
    if (_opacity < 1)
    {
        return false;
    }
    const csmInt32 count = _modelSetting->GetHitAreasCount();
    for (csmInt32 i = 0; i < count; i++)
    {
        if (strcmp(_modelSetting->GetHitAreaName(i), hitAreaName) == 0)
        {
            const CubismIdHandle drawID = _modelSetting->GetHitAreaId(i);
            return IsHit(drawID, x, y);
        }
    }
    return false; // 存在しない場合はfalse
}

void LAppModel::SetExpression(const csmChar* expressionID)
{
    ACubismMotion* motion = _expressions[expressionID];
    if (_debugMode)
    {
        LAppPal::PrintLogLn("[APP]expression: [%s]", expressionID);
    }

    if (motion != NULL)
    {
        _expressionManager->StartMotion(motion, false);
    }
    else
    {
        if (_debugMode)
        {
            LAppPal::PrintLogLn("[APP]expression[%s] is null ", expressionID);
        }
    }
}

void LAppModel::SetRandomExpression()
{
    if (_expressions.GetSize() == 0)
    {
        return;
    }

    csmInt32 no = rand() % _expressions.GetSize();
    csmMap<csmString, ACubismMotion*>::const_iterator map_ite;
    csmInt32 i = 0;
    for (map_ite = _expressions.Begin(); map_ite != _expressions.End(); map_ite++)
    {
        if (i == no)
        {
            csmString name = (*map_ite).First;
            SetExpression(name.GetRawString());
            return;
        }
        i++;
    }
}

void LAppModel::ReloadRenderer()
{
    DeleteRenderer();

    CreateRenderer();

    SetupTextures();
}

void LAppModel::SetupTextures()
{
    for (csmInt32 modelTextureNumber = 0; modelTextureNumber < _modelSetting->GetTextureCount(); modelTextureNumber++)
    {
        // テクスチャ名が空文字だった場合はロード・バインド処理をスキップ
        if (!strcmp(_modelSetting->GetTextureFileName(modelTextureNumber), ""))
        {
            continue;
        }

        //Metalテクスチャにテクスチャをロードする
        csmString texturePath = _modelSetting->GetTextureFileName(modelTextureNumber);
        texturePath = _modelHomeDir + texturePath;

//        AppDelegate *delegate = (AppDelegate *) [[UIApplication sharedApplication] delegate];
        L2DCubism *delegate = [L2DCubism sharedInstance];
        TextureInfo* texture = [[delegate getTextureManager] createTextureFromPngFile:texturePath.GetRawString()];
        id <MTLTexture> mtlTextueNumber = texture->id;

        //Metal
        GetRenderer<Rendering::CubismRenderer_Metal>()->BindTexture(modelTextureNumber, mtlTextueNumber);
    }

#ifdef PREMULTIPLIED_ALPHA_ENABLE
    GetRenderer<Rendering::CubismRenderer_Metal>()->IsPremultipliedAlpha(true);
#else
    GetRenderer<Rendering::CubismRenderer_Metal>()->IsPremultipliedAlpha(false);
#endif
}

void LAppModel::MotionEventFired(const csmString& eventValue)
{
    CubismLogInfo("%s is fired on LAppModel!!", eventValue.GetRawString());
}

Csm::Rendering::CubismOffscreenSurface_Metal& LAppModel::GetRenderBuffer()
{
    return _renderBuffer;
}

csmBool LAppModel::HasMocConsistencyFromFile(const csmChar* mocFileName)
{
    CSM_ASSERT(strcmp(mocFileName, ""));

    csmByte* buffer;
    csmSizeInt size;

    csmString path = mocFileName;
    path = _modelHomeDir + path;

    buffer = CreateBuffer(path.GetRawString(), &size);

    csmBool consistency = CubismMoc::HasMocConsistencyFromUnrevivedMoc(buffer, size);
    if (!consistency)
    {
        CubismLogInfo("Inconsistent MOC3.");
    }
    else
    {
        CubismLogInfo("Consistent MOC3.");
    }

    DeleteBuffer(buffer);

    return consistency;
}

void LAppModel::SetLipSyncValue(csmFloat32 mouth)
{
    if (_model == NULL || _lipSyncIds.GetSize() == 0)
    {
        return;
    }

    // 更新内部存储的lipSync值
    _lipSyncValue = mouth;

    // 设置口型参数到所有lipSync参数
//    for (csmUint32 i = 0; i < _lipSyncIds.GetSize(); ++i)
//    {
//        _model->SetParameterValue(_lipSyncIds[i], mouth);
//        if (_debugMode)
//        {
//            LAppPal::PrintLogLn("[APP]_lipSyncIds: [%s_%f]", _lipSyncIds[i]->GetString().GetRawString(), mouth);
//        }
//    }
}

void LAppModel::Release()
{
    // 确保 _modelSetting 存在，防止重复释放
    if (!_modelSetting)
    {
        return;
    }

    NSLog(@"[DEBUG] LAppModel Release model resource: %s", _modelSetting->GetModelFileName());

    _renderBuffer.DestroyOffscreenSurface();

    ReleaseMotions();
    ReleaseExpressions();

    for (csmInt32 i = 0; i < _modelSetting->GetMotionGroupCount(); i++)
    {
        const csmChar* group = _modelSetting->GetMotionGroupName(i);
        ReleaseMotionGroup(group);
    }

    // 释放Live2D SDK 内部对象
    L2DCubism *delegate = [L2DCubism sharedInstance];
    LAppTextureManager *textureManager = [delegate getTextureManager];

    if (textureManager) {
        for (csmInt32 modelTextureNumber = 0; modelTextureNumber < _modelSetting->GetTextureCount(); modelTextureNumber++)
        {
            // テクスチャ名が空文字だった場合は削除処理をスキップ
            if (!strcmp(_modelSetting->GetTextureFileName(modelTextureNumber), ""))
            {
                continue;
            }
//        id<MTLTexture> tex = GetRenderer<Rendering::CubismRenderer_Metal>()->GetBindedTextureId(modelTextureNumber);   // SDK 提供的接口取已绑定纹理
//        if (tex)
//        {
//            NSLog(@"[DEBUG] LAppModel: Release texture:%p", tex);
//            tex = nil; // 释放纹理
//        }
            //テクスチャ管理クラスからモデルテクスチャを削除する
            csmString texturePath = _modelSetting->GetTextureFileName(modelTextureNumber);
            texturePath = _modelHomeDir + texturePath;
            NSLog(@"[DEBUG] LAppModel: Release texturePath:%s", texturePath.GetRawString());
            [textureManager releaseTextureByName:texturePath.GetRawString()];
        }
    }

    CubismEyeBlink::Delete(_eyeBlink); // <-- 新增：释放眨眼控制器
    _eyeBlink = NULL;

    CubismBreath::Delete(_breath);     // <-- 新增：释放呼吸控制器
    _breath = NULL;

    CubismPose::Delete(_pose);
    _pose = NULL;

    CubismPhysics::Delete(_physics);
    _physics = NULL;

    Rendering::CubismRenderer_Metal::StaticRelease(); // 释放静态管线/缓存
    // 销毁渲染器和渲染目标
    DeleteRenderer(); // <-- 新增：释放渲染器

    // 5. 最后释放模型设置对象
    delete _modelSetting;
    _modelSetting = NULL;
}
