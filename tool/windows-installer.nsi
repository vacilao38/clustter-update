; -*- coding: utf-8 -*-
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WordFunc.nsh"
Name "${APP_NAME} ${APP_VERSION}"
OutFile "${OUTPUT}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\Clustter cores\${APP_NAME}"
InstallDirRegKey HKCU "Software\Clustter cores\${REG_ID}" "InstallDir"
SetCompressor lzma
ManifestDPIAware true
ShowInstDetails show
ShowUninstDetails show
VIProductVersion "${NUMERIC_VERSION}"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "Clustter cores"
VIAddVersionKey "FileDescription" "Instalador ${APP_NAME}"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "Clustter cores"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "${APP_NAME} está chegando."
!define MUI_WELCOMEPAGE_TEXT "Instale ou atualize o ${APP_NAME} neste usuário do Windows.$\r$\n$\r$\nSeus projetos, biblioteca e preferências são preservados.$\r$\n$\r$\nFeche o aplicativo antes de continuar."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Abrir ${APP_NAME}"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "PortugueseBR"

Function .onInit
  SetShellVarContext current
  SetRegView 32
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "Este instalador precisa do Windows 10/11 de 64 bits."
    Abort
  ${EndIf}
  ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "DisplayVersion"
  ${If} $0 != ""
    ${VersionCompare} $0 "${APP_VERSION}" $1
    ${If} $1 == 1
      MessageBox MB_OK|MB_ICONSTOP "Uma versão mais recente do ${APP_NAME} já está instalada."
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd
Function un.onInit
  SetShellVarContext current
  SetRegView 32
FunctionEnd

!macro ClosedCheck PREFIX
Function ${PREFIX}EnsureClosed
  IfFileExists "$INSTDIR\${APP_EXE}" 0 done
retry:
  ClearErrors
  FileOpen $0 "$INSTDIR\${APP_EXE}" a
  IfErrors locked
  FileClose $0
  Goto done
locked:
  ${If} ${Silent}
    SetErrorLevel 2
    Abort
  ${EndIf}
  MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Feche o ${APP_NAME} para continuar. Seu trabalho não será encerrado à força." IDRETRY retry
  SetErrorLevel 2
  Abort
done:
FunctionEnd
!macroend
!insertmacro ClosedCheck ""
!insertmacro ClosedCheck "un."

Section "${APP_NAME}"
  Call EnsureClosed
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /r "${PAYLOAD}\*"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\Clustter cores\${REG_ID}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "DisplayName" "${APP_NAME} · Clustter cores"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "Publisher" "Clustter cores"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "UninstallString" '$\"$INSTDIR\uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "QuietUninstallString" '$\"$INSTDIR\uninstall.exe$\" /S'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "URLInfoAbout" "https://vacilao38.github.io/clustter-cores-downloads/#${APP_ID}"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}" "NoRepair" 1
!ifndef TEST_BUILD
!ifdef BROWSER_HOST
  WriteRegStr HKCU "Software\Google\Chrome\NativeMessagingHosts\com.clustter.chain" "" "$INSTDIR\chain-browser-host.json"
  WriteRegStr HKCU "Software\Microsoft\Edge\NativeMessagingHosts\com.clustter.chain" "" "$INSTDIR\chain-browser-host.json"
!endif
  CreateDirectory "$SMPROGRAMS\Clustter cores"
  CreateShortcut "$SMPROGRAMS\Clustter cores\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
!endif
SectionEnd

Section "Uninstall"
  Call un.EnsureClosed
!ifndef TEST_BUILD
!ifdef BROWSER_HOST
  ReadRegStr $0 HKCU "Software\Google\Chrome\NativeMessagingHosts\com.clustter.chain" ""
  ${If} $0 == "$INSTDIR\chain-browser-host.json"
    DeleteRegKey HKCU "Software\Google\Chrome\NativeMessagingHosts\com.clustter.chain"
  ${EndIf}
  ReadRegStr $0 HKCU "Software\Microsoft\Edge\NativeMessagingHosts\com.clustter.chain" ""
  ${If} $0 == "$INSTDIR\chain-browser-host.json"
    DeleteRegKey HKCU "Software\Microsoft\Edge\NativeMessagingHosts\com.clustter.chain"
  ${EndIf}
!endif
!endif
  ; Generated exact file list: never recursively delete an install/user folder.
  !include "${UNINSTALL_FILES}"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
!ifndef TEST_BUILD
  Delete "$SMPROGRAMS\Clustter cores\${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\Clustter cores"
!endif
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClustterCore.${REG_ID}"
  DeleteRegKey HKCU "Software\Clustter cores\${REG_ID}"
SectionEnd
