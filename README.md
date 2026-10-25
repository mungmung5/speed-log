# Speed Log

개인용 아이폰 차량 운행 기록 앱입니다.

## 기능

- 출발부터 도착까지 운행 시간, 거리, 평균 속도, 최고 속도 기록
- 속도별 색으로 나눈 주행 경로 지도, 속도 그래프
- 월별로 묶은 운행 목록과 월별 통계
- 자동 시작(차량 이동 감지)·자동 종료(정차 시간 기준)
- 단축어 연동: 차 블루투스 연결/해제 시 기록 시작/종료
- 백업 내보내기·불러오기, 엑셀(CSV)·GPX 내보내기

## 빌드

`main`에 코드가 올라오면 GitHub Actions가 클라우드 Mac에서 서명 없는 IPA를 빌드해
[Releases](../../releases/latest)에 올립니다. 프로젝트 파일은 `project.yml`(XcodeGen)로 만듭니다.

## 설치 (무료 Apple ID)

1. Windows PC에 AltServer를 설치하고 아이폰에 AltStore를 설치
2. 아이폰 **설정 › 개인정보 보호 및 보안 › 개발자 모드** 켜기
3. 아이폰 Safari에서 Releases의 `SpeedLog.ipa`를 내려받기
4. AltStore › My Apps › **+** 에서 내려받은 IPA 선택

무료 Apple ID로 설치한 앱은 7일마다 갱신해야 합니다. 아이폰과 PC가 같은 와이파이에
있으면 AltStore가 자동으로 갱신합니다. 갱신해도 기록은 그대로 남습니다.
