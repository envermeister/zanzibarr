# UseNews yerel çatalı: framework'ler artık CI'dan İNDİRİLMEZ.
# Mpv.xcframework, tools/bundle_mpv_framework.py ile homebrew libmpv 0.40 +
# tam FFmpeg'ten üretilip depoya gömülüdür. Bu hedef yalnız media_kit_video
# pod'unun beklediği .symlinks/mpv/macos bağını kurar.

all: Frameworks/.symlinks

Frameworks/.symlinks: Frameworks/Mpv.xcframework
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sed -i '' 's/\r$$//g' create_framework_symlinks.sh
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv

.PHONY: clean
clean:
	rm -rf Frameworks/.symlinks
