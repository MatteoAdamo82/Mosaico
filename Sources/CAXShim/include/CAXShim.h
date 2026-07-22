#ifndef CAXSHIM_H
#define CAXSHIM_H

#include <ApplicationServices/ApplicationServices.h>
#include <CoreGraphics/CoreGraphics.h>

// SPI di ApplicationServices usata anche da Amethyst/AeroSpace/Rectangle:
// restituisce il CGWindowID di un AXUIElement finestra. Nessun requisito
// di entitlement o SIP; è l'unico modo stabile per correlare AX <-> CGWindowList.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

static inline AXError MosaicoGetWindowID(AXUIElementRef element, CGWindowID *windowID) {
    return _AXUIElementGetWindow(element, windowID);
}

// SPI SkyLight/CoreGraphics per gli Spaces nativi (le stesse usate da
// yabai/AltTab; funzionano con SIP attivo):
typedef size_t CGSConnectionID;
extern CGSConnectionID CGSMainConnectionID(void);
// Array di dict per display: "Display Identifier", "Current Space" -> {"id64"}
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid);
// Space id per ogni finestra richiesta (mask 0x7 = tutti gli space)
extern CFArrayRef CGSCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windowIDs);

#endif
