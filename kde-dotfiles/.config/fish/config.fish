if status is-interactive
    # Commands to run in interactive sessions can go here
end
set fish_greeting ""


starship init fish | source
zoxide init fish --cmd cd | source

function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

function ls
	command eza $argv
end

thefuck --alias | source
# fa运行fastfetch
abbr fa fastfetch
# f运行带二次元美少女的fastfetch
function f 
    command bash $HOME/.config/scripts/fastfetch-random-wife.sh
   end
# fzf安装软件包
function pac --description "Fuzzy search and install packages (Official Repo first)"
    # --- 配置区域 ---
    # 1. 定义颜色 (ANSI 标准色，兼容 Matugen)
    set color_official  "\033[34m"   
    set color_aur       "\033[35m"   
    set color_reset     "\033[0m"

    # 2. AUR 净化过滤器 (正则)
    # 修复点：这里必须用单引号 ''，否则正则表达式末尾的 $ 会被 fish 误判为变量
    set aur_filter      '^(mingw-|lib32-|cross-|.*-debug$)'

    # --- 逻辑区域 ---
    set preview_cmd 'yay -Si {2}'

    # 生成列表 -> 过滤 -> 上色 -> fzf
    set packages (begin
        # 1. 官方源：蓝色前缀
        pacman -Sl | awk -v c=$color_official -v r=$color_reset \
            '{printf "%s%-10s%s %-30s %s\n", c, $1, r, $2, $3}'

        # 2. AUR 源：紫色前缀 + 过滤垃圾包
        yay -Sl aur | grep -vE "$aur_filter" | awk -v c=$color_aur -v r=$color_reset \
            '{printf "%s%-10s%s %-30s %s\n", c, $1, r, $2, $3}'
    end | \
    fzf --multi --ansi \
        --preview $preview_cmd --preview-window=right:60%:wrap \
        --height=95% --layout=reverse --border \
        --tiebreak=index \
        --nth=2 \
        --header 'Tab:多选 | Enter:安装 | Esc:退出' \
        --query "$argv" | \
    awk '{print $2}') # 直接提取纯净包名

    # --- 执行安装 ---
    if test -n "$packages"
        echo "正在准备安装: $packages"
        # 修复点：直接使用 $packages 列表，不要再用 awk 处理，否则多选会失效
        yay -S $packages
    end
end
# fzf卸载软件包
function pacr --description "Fuzzy find and remove packages (UI matched with pac)"
    # --- 配置区域 ---
    # 1. 定义颜色 (保持与 pac 一致)
    set color_official  "\033[34m"    
    set color_aur       "\033[35m"    
    set color_reset     "\033[0m"

    # --- 逻辑区域 ---
    # 预览命令：查询本地已安装详细信息 (-Qi)，目标是第2列(包名)
    set preview_cmd 'yay -Qi {2}'

    # 生成列表 -> 上色 -> fzf
    set packages (begin
        # 1. 官方源安装 (Native): 蓝色前缀 [local]
        pacman -Qn | awk -v c=$color_official -v r=$color_reset \
            '{printf "%s%-10s%s %-30s %s\n", c, "local", r, $1, $2}'

        # 2. AUR/外部源安装 (Foreign): 紫色前缀 [aur]
        pacman -Qm | awk -v c=$color_aur -v r=$color_reset \
            '{printf "%s%-10s%s %-30s %s\n", c, "aur", r, $1, $2}'
    end | \
    fzf --multi --ansi \
        --preview $preview_cmd --preview-window=right:60%:wrap \
        --height=95% --layout=reverse --border \
        --tiebreak=index \
        --nth=2 \
        --header 'Tab:多选 | Enter:卸载 | Esc:退出' \
        --query "$argv" | \
    awk '{print $2}') # 提取第2列纯净包名

    # --- 执行卸载 ---
    if test -n "$packages"
        echo "正在准备卸载: $packages"
        # -Rns: 递归删除配置文件和不再需要的依赖
        yay -Rns $packages
    end
end
