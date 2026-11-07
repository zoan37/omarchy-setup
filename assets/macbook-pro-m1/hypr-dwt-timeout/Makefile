PLUGIN_NAME = dwt-timeout
SOURCES = $(wildcard src/*.cpp)
CXXFLAGS += -shared -fPIC --no-gnu-unique -std=c++2b -Wall -O2 -g
PKGS = pixman-1 libdrm hyprland libinput

all: $(PLUGIN_NAME).so

$(PLUGIN_NAME).so: $(SOURCES)
	$(CXX) -o $@ $(SOURCES) $(CXXFLAGS) $(shell pkg-config --cflags $(PKGS)) $(shell pkg-config --libs libinput)

clean:
	rm -f $(PLUGIN_NAME).so

.PHONY: all clean
