# 临时侦查：解析 robot_body.tscn 里 Attack1 动画的轨道与旋转幅度
import re

text = open('scenes/monsters/robot_body.tscn', encoding='utf-8').read()
blocks = re.split(r'\[sub_resource type="Animation" ', text)
for b in blocks:
    if 'resource_name = "Attack1"' in b[:300]:
        paths = re.findall(r'tracks/(\d+)/path = &"([^"]+)"', b)
        print('Attack1 轨道数:', len(paths))
        for idx, path in paths:
            print(' ', path)
        # 提取每个 rotation 轨道（type=4? 在 tscn 中 type 0=position 1=rotation 2=scale 3=blend 4=method 5=value...）
        # 实际 Animation.TYPE_POSITION_3D=0, ROTATION_3D=1, SCALE_3D=2
        # 逐轨道抓 keys 并算四元数夹角
        track_types = re.findall(r'tracks/(\d+)/type = (\d+)', b)
        tmap = dict(track_types)
        for idx, path in paths:
            ttype = tmap.get(idx)
            if ttype != '1':  # 只看旋转
                continue
            seg = re.search(r'tracks/%s/keys = \[[^\]]*\]' % idx, b, re.S)
            if not seg:
                continue
            quats = re.findall(r'\(\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+)\)', seg.group(0))
            if len(quats) < 2:
                continue
            def dot(a, b):
                return sum(float(x) * float(y) for x, y in zip(a, b))
            first = quats[0]
            max_ang = 0.0
            for q in quats[1:]:
                d = abs(dot(first, q))
                d = min(1.0, d)
                import math
                ang = math.degrees(2 * math.acos(d))
                max_ang = max(max_ang, ang)
            print('旋转轨道 %s: 关键帧 %d, 相对首帧最大旋转 %.0f°' % (path, len(quats), max_ang))
        break
