import os
import json
import tkinter as tk
from tkinter import simpledialog, messagebox, ttk
from datetime import datetime
import time

DATA_FILE = "courier_data.json"
SETTINGS_FILE = "settings.json"

# --- COLOR PALETTE ---
BG_APP = "#0c0c0d"
BG_SIDEBAR = "#121214"
BG_CARD = "#17171a"
BG_INPUT = "#080809"
BG_TITLEBAR = "#111111"
BORDER_DARK = "#232328"
BORDER_COLOR = "#232328"
BORDER_HIGHLIGHT = "#32323a"
ACCENT_GREEN = "#a8d944"
ACCENT_ORANGE = "#e5a144"
ACCENT_BLUE = "#44a8e5"
ACCENT_CYAN = "#44d9e5"
ACCENT_PURPLE = "#a370f7"
TEXT_WHITE = "#f0f0f2"
TEXT_MUTED = "#7a7a85"
ERR_RED = "#e54444"

DEFAULT_PRESETS = {
    "Maxon Matador 125cc (Skútr)": {
        "engine_oil_interval": 2500,
        "gear_oil_interval": 5000,
        "spark_plug_interval": 5000
    },
    "Univerzální Skútr 50cc 4T": {
        "engine_oil_interval": 2000,
        "gear_oil_interval": 4000,
        "spark_plug_interval": 4000
    },
    "Osobní auto (Benzín / Nafta)": {
        "engine_oil_interval": 10000,
        "gear_oil_interval": 60000,
        "spark_plug_interval": 30000
    }
}

vybrany_typ = "DYSKO"
active_hist_filter = "ALL"  # "ALL", "dyska", "palivo", "km"
shift_start_time = None
shift_start_dt = None
shift_start_totals = None
shift_active = False
is_maximized = False
prev_geom = "960x680+80+40"

# --- DATA STORAGE ---
def load_settings():
    default_cfg = {
        "active_preset": "Maxon Matador 125cc (Skútr)",
        "presets": DEFAULT_PRESETS,
        "service_history": {
            "last_engine_oil_km": 0,
            "last_gear_oil_km": 0,
            "last_spark_plug_km": 0
        }
    }
    if not os.path.exists(SETTINGS_FILE):
        save_settings(default_cfg)
        return default_cfg
    try:
        with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
            if "presets" not in cfg or not cfg["presets"]:
                cfg["presets"] = DEFAULT_PRESETS
            if "active_preset" not in cfg or cfg["active_preset"] not in cfg["presets"]:
                cfg["active_preset"] = list(cfg["presets"].keys())[0]
            if "service_history" not in cfg:
                cfg["service_history"] = default_cfg["service_history"]
            return cfg
    except Exception:
        return default_cfg

def save_settings(cfg):
    with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=4, ensure_ascii=False)

def load_data():
    default_data = {"dyska": [], "palivo": [], "km": [], "shifts": []}
    if not os.path.exists(DATA_FILE):
        save_data(default_data)
        return default_data
    try:
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            if "shifts" not in data:
                data["shifts"] = []
            return data
    except Exception:
        return default_data

def save_data(data):
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)

# --- CALCULATIONS ---
def get_totals():
    data = load_data()
    dyska = sum(e["hodnota"] for e in data.get("dyska", []))
    palivo = sum(e["hodnota"] for e in data.get("palivo", []))
    km = sum(e["hodnota"] for e in data.get("km", []))
    dropy = len(data.get("dyska", []))
    return dyska, palivo, km, dropy

def refresh_ui():
    dyska, palivo, km, dropy = get_totals()
    bilance = dyska - palivo

    card_val_profit.config(text=f"{bilance:+.0f} Kč", fg=ACCENT_GREEN if bilance >= 0 else ERR_RED)
    card_val_dyska.config(text=f"+{dyska:.0f} Kč")
    card_val_palivo.config(text=f"-{palivo:.0f} Kč")
    card_val_km.config(text=f"{km:.0f} km")
    card_val_drops.config(text=str(dropy))
    
    avg_tip = (dyska / dropy) if dropy > 0 else 0
    card_val_avg.config(text=f"{avg_tip:.1f} Kč")

    cfg = load_settings()
    active_name = cfg.get("active_preset", list(cfg["presets"].keys())[0])
    active_profile = cfg["presets"].get(active_name, list(cfg["presets"].values())[0])
    svc = cfg.get("service_history", {})
    
    svc_header_title.config(text=f"SERVISNÍ DENÍK // {active_name.upper()}")
    lbl_desc_engine.config(text=f"Výměna motorového oleje (Interval: {active_profile['engine_oil_interval']:.0f} km)")
    lbl_desc_gear.config(text=f"Výměna převodového oleje (Interval: {active_profile['gear_oil_interval']:.0f} km)")
    lbl_desc_spark.config(text=f"Kontrola/výměna svíčky a filtru (Interval: {active_profile['spark_plug_interval']:.0f} km)")

    rem_engine = float(active_profile["engine_oil_interval"]) - (km - float(svc.get("last_engine_oil_km", 0)))
    rem_gear = float(active_profile["gear_oil_interval"]) - (km - float(svc.get("last_gear_oil_km", 0)))
    rem_spark = float(active_profile["spark_plug_interval"]) - (km - float(svc.get("last_spark_plug_km", 0)))

    val_svc_engine.config(text=f"{rem_engine:.0f} km", fg=ACCENT_GREEN if rem_engine > 0 else ERR_RED)
    val_svc_gear.config(text=f"{rem_gear:.0f} km", fg=ACCENT_GREEN if rem_gear > 0 else ERR_RED)
    val_svc_spark.config(text=f"{rem_spark:.0f} km", fg=ACCENT_GREEN if rem_spark > 0 else ERR_RED)

    
    query = entry_search.get().strip().lower()
    data = load_data()
    
    for row in tree_history.get_children():
        tree_history.delete(row)

    all_events = []
    if active_hist_filter in ("ALL", "dyska"):
        for d in data.get("dyska", []):
            all_events.append({"typ": "DÝŠKO", "cas": d["cas"], "hodnota": f"+{d['hodnota']:.0f} Kč", "tag": "green", "cat": "dyska", "raw": d["hodnota"]})
    if active_hist_filter in ("ALL", "palivo"):
        for p in data.get("palivo", []):
            all_events.append({"typ": "PALIVO", "cas": p["cas"], "hodnota": f"-{p['hodnota']:.0f} Kč", "tag": "orange", "cat": "palivo", "raw": p["hodnota"]})
    if active_hist_filter in ("ALL", "km"):
        for k in data.get("km", []):
            all_events.append({"typ": "KILOMETRY", "cas": k["cas"], "hodnota": f"{k['hodnota']:.0f} km", "tag": "blue", "cat": "km", "raw": k["hodnota"]})

    all_events.reverse()
    for e in all_events:
        match_str = f"{e['typ']} {e['cas']} {e['hodnota']}".lower()
        if not query or query in match_str:
            tree_history.insert("", "end", values=(e["typ"], e["cas"], e["hodnota"]), tags=(e["tag"],))

    # Obnova směn
    for row in tree_shifts.get_children():
        tree_shifts.delete(row)
    shifts = list(data.get("shifts", []))
    shifts.reverse()
    for s in shifts:
        tree_shifts.insert("", "end", values=(
            s.get("datum", ""),
            s.get("trvani", ""),
            f"{s.get('zisk', 0):+.0f} Kč",
            f"{s.get('hodinovka', 0):.0f} Kč/h",
            s.get("dropy", 0),
            f"{s.get('km', 0):.0f} km"
        ), tags=("profit_pos" if s.get("zisk", 0) >= 0 else "profit_neg",))

# --- TREEVIEW MULTI-SELECT TOGGLE ---
def toggle_tree_selection(event):
    region = tree_history.identify("region", event.x, event.y)
    if region != "cell":
        return
    item = tree_history.identify_row(event.y)
    if not item:
        return
    current = list(tree_history.selection())
    if item in current:
        current.remove(item)
    else:
        current.append(item)
    tree_history.selection_set(current)
    return "break"

def toggle_shifts_selection(event):
    region = tree_shifts.identify("region", event.x, event.y)
    if region != "cell":
        return
    item = tree_shifts.identify_row(event.y)
    if not item:
        return
    current = list(tree_shifts.selection())
    if item in current:
        current.remove(item)
    else:
        current.append(item)
    tree_shifts.selection_set(current)
    return "break"

# --- SHIFT LOGIC ---
def toggle_shift():
    global shift_active, shift_start_time, shift_start_dt, shift_start_totals
    if not shift_active:
        shift_active = True
        shift_start_time = time.time()
        shift_start_dt = datetime.now()
        shift_start_totals = get_totals()
        btn_shift.config(text="⏹ STOP SMĚNY", fg=ERR_RED)
        update_shift_timer()
    else:
        shift_active = False
        btn_shift.config(text="▶ START SMĚNY", fg=ACCENT_CYAN)
        elapsed_sec = int(time.time() - shift_start_time)
        hrs, rem = divmod(elapsed_sec, 3600)
        mins, secs = divmod(rem, 60)
        duration_str = f"{hrs:02d}:{mins:02d}:{secs:02d}"

        end_totals = get_totals()
        d_shift = end_totals[0] - shift_start_totals[0]
        p_shift = end_totals[1] - shift_start_totals[1]
        km_shift = end_totals[2] - shift_start_totals[2]
        drops_shift = end_totals[3] - shift_start_totals[3]
        profit_shift = d_shift - p_shift
        hours_float = max(elapsed_sec / 3600.0, 1.0 / 60.0)
        hourly_rate = profit_shift / hours_float

        shift_record = {
            "datum": shift_start_dt.strftime("%d.%m.%Y %H:%M"),
            "trvani": duration_str,
            "zisk": profit_shift,
            "dyska": d_shift,
            "palivo": p_shift,
            "km": km_shift,
            "dropy": drops_shift,
            "hodinovka": hourly_rate
        }

        data = load_data()
        data["shifts"].append(shift_record)
        save_data(data)
        lbl_shift_timer.config(text="00:00:00")
        refresh_ui()
        messagebox.showinfo(
            "Směna ukončena",
            f"Směna úspěšně uložena!\n\n"
            f"⏱ Trvání: {duration_str}\n"
            f"💰 Čistý zisk: {profit_shift:+.0f} Kč\n"
            f"⚡ Hodinovka: {hourly_rate:.0f} Kč/h\n"
            f"🛵 Nájezd: {km_shift:.0f} km | Dropy: {drops_shift}",
            parent=okno
        )

def update_shift_timer():
    if shift_active and shift_start_time:
        elapsed_sec = int(time.time() - shift_start_time)
        hrs, rem = divmod(elapsed_sec, 3600)
        mins, secs = divmod(rem, 60)
        lbl_shift_timer.config(text=f"{hrs:02d}:{mins:02d}:{secs:02d}")
        okno.after(1000, update_shift_timer)

def set_history_filter(filter_mode):
    global active_hist_filter
    active_hist_filter = filter_mode
    for btn, mode in [
        (btn_flt_all, "ALL"),
        (btn_flt_dyska, "dyska"),
        (btn_flt_palivo, "palivo"),
        (btn_flt_km, "km")
    ]:
        if mode == filter_mode:
            btn.config(bg=BG_CARD, fg=TEXT_WHITE)
        else:
            btn.config(bg=BG_APP, fg=TEXT_MUTED)
    refresh_ui()

# --- ACTIONS ---
def nastav_typ(novy_typ):
    global vybrany_typ
    vybrany_typ = novy_typ
    btn_type_dysko.config(fg=TEXT_MUTED, bg=BG_APP)
    btn_type_palivo.config(fg=TEXT_MUTED, bg=BG_APP)
    btn_type_km.config(fg=TEXT_MUTED, bg=BG_APP)
    
    if novy_typ == "DYSKO":
        btn_type_dysko.config(fg=ACCENT_GREEN, bg=BG_CARD)
        input_label.config(text="ZADEJ ČÁSTKU DÝŠKA (KČ):")
        btn_submit.config(text="ZAPSAT DÝŠKO [Enter]", fg=ACCENT_GREEN)
    elif novy_typ == "PALIVO":
        btn_type_palivo.config(fg=ACCENT_ORANGE, bg=BG_CARD)
        input_label.config(text="ZADEJ ÚTRATU ZA PALIVO (KČ):")
        btn_submit.config(text="ZAPSAT PALIVO [Enter]", fg=ACCENT_ORANGE)
    else:
        btn_type_km.config(fg=ACCENT_BLUE, bg=BG_CARD)
        input_label.config(text="ZADEJ UJETÉ KILOMETRY (KM):")
        btn_submit.config(text="ZAPSAT KILOMETRY [Enter]", fg=ACCENT_BLUE)

def execute_log(event=None):
    text_vstup = entry_val.get().strip()
    try:
        val = float(text_vstup)
        if val <= 0:
            status_label.config(text="[-] Částka musí být větší než 0", fg=ERR_RED)
            return
    except ValueError:
        status_label.config(text="[-] Zadávej pouze platná čísla!", fg=ERR_RED)
        return

    cas = datetime.now().strftime("%d.%m. %H:%M")
    data = load_data()
    
    if vybrany_typ == "DYSKO":
        data["dyska"].append({"cas": cas, "hodnota": val})
        status_label.config(text=f"[+] Zapsáno dýško: +{val:.0f} Kč", fg=ACCENT_GREEN)
    elif vybrany_typ == "PALIVO":
        data["palivo"].append({"cas": cas, "hodnota": val})
        status_label.config(text=f"[+] Zapsáno palivo: -{val:.0f} Kč", fg=ACCENT_ORANGE)
    else:
        data["km"].append({"cas": cas, "hodnota": val})
        status_label.config(text=f"[+] Zapsáno: {val:.0f} km", fg=ACCENT_BLUE)

    save_data(data)
    entry_val.delete(0, tk.END)
    refresh_ui()

def reset_service(service_key, title):
    if messagebox.askyesno("Servisní úkon", f"Potvrdit provedení servisu ({title})?\nOdpočet kilometrů bude resetován.", parent=okno):
        cfg = load_settings()
        _, _, total_km, _ = get_totals()
        cfg["service_history"][service_key] = total_km
        save_settings(cfg)
        refresh_ui()

def delete_selected_history():
    selected = tree_history.selection()
    if not selected:
        messagebox.showinfo("Informace", "Nejsou označeny žádné položky ke smazání.", parent=okno)
        return
    data = load_data()
    for item_id in selected:
        vals = tree_history.item(item_id, "values")
        typ, cas, hodn = vals[0], vals[1], vals[2]
        cat = "dyska" if typ == "DÝŠKO" else ("palivo" if typ == "PALIVO" else "km")
        clean_val = float(hodn.replace(" Kč", "").replace(" km", "").replace("+", "").replace("-", ""))
        for entry in list(data[cat]):
            if entry["cas"] == cas and entry["hodnota"] == clean_val:
                data[cat].remove(entry)
                break
    save_data(data)
    refresh_ui()

def clear_entire_history():
    if messagebox.askyesno("Smazat vše", "Opravdu chceš vymazat celou historii záznamů?", parent=okno):
        data = load_data()
        data["dyska"] = []
        data["palivo"] = []
        data["km"] = []
        save_data(data)
        refresh_ui()

def delete_selected_shifts():
    selected = tree_shifts.selection()
    if not selected:
        messagebox.showinfo("Informace", "Nejsou označeny žádné směny ke smazání.", parent=okno)
        return
    data = load_data()
    for item_id in selected:
        vals = tree_shifts.item(item_id, "values")
        datum = vals[0]
        for s in list(data.get("shifts", [])):
            if s.get("datum") == datum:
                data["shifts"].remove(s)
                break
    save_data(data)
    refresh_ui()

def clear_all_shifts():
    if messagebox.askyesno("Smazat směny", "Opravdu chceš vymazat celou historii směn?", parent=okno):
        data = load_data()
        data["shifts"] = []
        save_data(data)
        refresh_ui()

def export_csv():
    data = load_data()
    vystup = "kuryr_export.csv"
    with open(vystup, "w", encoding="utf-8") as f:
        f.write("Kategorie;Datum_Cas;Hodnota\n")
        for kat in ["dyska", "palivo", "km"]:
            for item in data.get(kat, []):
                f.write(f"{kat.upper()};{item['cas']};{item['hodnota']:.0f}\n")
    messagebox.showinfo("Export", f"Export úspěšně uložen do:\n{vystup}", parent=okno)

# --- SETTINGS / PROFILES LOGIC ---
def on_preset_select(event=None):
    cfg = load_settings()
    selected = preset_combo.get()
    if selected in cfg["presets"]:
        p = cfg["presets"][selected]
        entry_cfg_engine.delete(0, tk.END)
        entry_cfg_engine.insert(0, str(int(p["engine_oil_interval"])))
        entry_cfg_gear.delete(0, tk.END)
        entry_cfg_gear.insert(0, str(int(p["gear_oil_interval"])))
        entry_cfg_spark.delete(0, tk.END)
        entry_cfg_spark.insert(0, str(int(p["spark_plug_interval"])))

def save_cfg_profile():
    cfg = load_settings()
    active_p = preset_combo.get().strip()
    if not active_p:
        return
    try:
        e_oil = float(entry_cfg_engine.get().strip())
        g_oil = float(entry_cfg_gear.get().strip())
        s_plug = float(entry_cfg_spark.get().strip())
        if e_oil <= 0 or g_oil <= 0 or s_plug <= 0:
            messagebox.showerror("Chyba", "Intervaly musí být kladná čísla!", parent=okno)
            return
    except ValueError:
        messagebox.showerror("Chyba", "Zadávej pouze platná čísla kilometrů!", parent=okno)
        return

    cfg["active_preset"] = active_p
    cfg["presets"][active_p] = {
        "engine_oil_interval": e_oil,
        "gear_oil_interval": g_oil,
        "spark_plug_interval": s_plug
    }
    save_settings(cfg)
    preset_combo["values"] = list(cfg["presets"].keys())
    preset_combo.set(active_p)
    messagebox.showinfo("Nastavení", f"Profil '{active_p}' byl úspěšně uložen.", parent=okno)
    refresh_ui()

def create_new_custom_profile():
    new_name = simpledialog.askstring("Nový profil vozidla", "Zadej název nového skútru / auta:", parent=okno)
    if new_name and new_name.strip():
        new_name = new_name.strip()
        cfg = load_settings()
        if new_name in cfg["presets"]:
            messagebox.showwarning("Upozornění", "Profil s tímto názvem již existuje.", parent=okno)
            preset_combo.set(new_name)
            on_preset_select()
            return
        cfg["presets"][new_name] = {
            "engine_oil_interval": 3000,
            "gear_oil_interval": 6000,
            "spark_plug_interval": 6000
        }
        cfg["active_preset"] = new_name
        save_settings(cfg)
        preset_combo["values"] = list(cfg["presets"].keys())
        preset_combo.set(new_name)
        on_preset_select()
        refresh_ui()
        messagebox.showinfo("Hotovo", f"Profil '{new_name}' byl vytvořen.", parent=okno)

# --- NAVIGATION ---
def switch_view(view_name):
    view_dashboard.pack_forget()
    view_history.pack_forget()
    view_shifts.pack_forget()
    view_service.pack_forget()
    view_settings.pack_forget()

    for btn in [nav_btn_dash, nav_btn_hist, nav_btn_shifts, nav_btn_svc, nav_btn_cfg]:
        btn.config(bg=BG_SIDEBAR, fg=TEXT_MUTED)

    if view_name == "dash":
        view_dashboard.pack(fill="both", expand=True)
        nav_btn_dash.config(bg=BG_CARD, fg=ACCENT_GREEN)
    elif view_name == "hist":
        view_history.pack(fill="both", expand=True)
        nav_btn_hist.config(bg=BG_CARD, fg=ACCENT_GREEN)
    elif view_name == "shifts":
        view_shifts.pack(fill="both", expand=True)
        nav_btn_shifts.config(bg=BG_CARD, fg=ACCENT_GREEN)
    elif view_name == "svc":
        view_service.pack(fill="both", expand=True)
        nav_btn_svc.config(bg=BG_CARD, fg=ACCENT_GREEN)
    else:
        view_settings.pack(fill="both", expand=True)
        nav_btn_cfg.config(bg=BG_CARD, fg=ACCENT_GREEN)
        on_preset_select()
    refresh_ui()

# --- WINDOW DRAG & CONTROLS ---
def start_move(event):
    okno.x_pos = event.x
    okno.y_pos = event.y

def do_move(event):
    if not is_maximized:
        okno.geometry(f"+{okno.winfo_x() + (event.x - okno.x_pos)}+{okno.winfo_y() + (event.y - okno.y_pos)}")

def toggle_maximize(event=None):
    global is_maximized, prev_geom
    if not is_maximized:
        prev_geom = okno.geometry()
        okno.geometry(f"{okno.winfo_screenwidth()}x{okno.winfo_screenheight()}+0+0")
        is_maximized = True
    else:
        okno.geometry(prev_geom)
        is_maximized = False

def start_resize(event):
    okno.rx_start = event.x_root
    okno.ry_start = event.y_root
    okno.rw_start = okno.winfo_width()
    okno.rh_start = okno.winfo_height()

def do_resize(event):
    if not is_maximized:
        w = max(880, okno.rw_start + (event.x_root - okno.rx_start))
        h = max(600, okno.rh_start + (event.y_root - okno.ry_start))
        okno.geometry(f"{w}x{h}")
        okno.update_idletasks()

# --- ROOT GUI ---
okno = tk.Tk()
okno.overrideredirect(True)
okno.geometry(prev_geom)
okno.configure(bg=BORDER_DARK)

app_wrapper = tk.Frame(okno, bg=BG_APP, highlightthickness=1, highlightbackground=BORDER_COLOR)
app_wrapper.pack(fill="both", expand=True, padx=1, pady=1)

tk.Frame(app_wrapper, bg=ACCENT_GREEN, height=2).pack(fill="x")
topbar = tk.Frame(app_wrapper, bg=BG_TITLEBAR, height=30)
topbar.pack(fill="x")

tk.Label(topbar, text="  Z3RYK0 | Kurýrská kalkulačka", font=("Consolas", 9, "bold"), bg=BG_TITLEBAR, fg=TEXT_WHITE).pack(side="left")

btn_close = tk.Button(topbar, text="✕", font=("Consolas", 9), bg=BG_TITLEBAR, fg=TEXT_MUTED, activebackground=ERR_RED, relief="flat", bd=0, command=okno.destroy)
btn_close.pack(side="right", padx=6)
btn_max = tk.Button(topbar, text="□", font=("Consolas", 9), bg=BG_TITLEBAR, fg=TEXT_MUTED, relief="flat", bd=0, command=toggle_maximize)
btn_max.pack(side="right", padx=2)
btn_min = tk.Button(topbar, text="—", font=("Consolas", 9), bg=BG_TITLEBAR, fg=TEXT_MUTED, relief="flat", bd=0, command=okno.iconify)
btn_min.pack(side="right", padx=2)

topbar.bind("<Button-1>", start_move)
topbar.bind("<B1-Motion>", do_move)
topbar.bind("<Double-Button-1>", toggle_maximize)

body = tk.Frame(app_wrapper, bg=BG_APP)
body.pack(fill="both", expand=True)

# ================= SIDEBAR =================
sidebar = tk.Frame(body, bg=BG_SIDEBAR, width=180, highlightthickness=1, highlightbackground=BORDER_COLOR)
sidebar.pack(side="left", fill="y")
sidebar.pack_propagate(False)

tk.Label(sidebar, text="PŘEHLEDY", font=("Consolas", 8, "bold"), bg=BG_SIDEBAR, fg=TEXT_MUTED).pack(anchor="w", padx=14, pady=(16, 6))

nav_btn_dash = tk.Button(sidebar, text="⚡ Dashboard", font=("Consolas", 10, "bold"), bg=BG_CARD, fg=ACCENT_GREEN, relief="flat", anchor="w", padx=12, command=lambda: switch_view("dash"))
nav_btn_dash.pack(fill="x", padx=6, pady=2, ipady=4)

nav_btn_hist = tk.Button(sidebar, text="📋 Záznamy", font=("Consolas", 10, "bold"), bg=BG_SIDEBAR, fg=TEXT_MUTED, relief="flat", anchor="w", padx=12, command=lambda: switch_view("hist"))
nav_btn_hist.pack(fill="x", padx=6, pady=2, ipady=4)

nav_btn_shifts = tk.Button(sidebar, text="⏱ Směny", font=("Consolas", 10, "bold"), bg=BG_SIDEBAR, fg=TEXT_MUTED, relief="flat", anchor="w", padx=12, command=lambda: switch_view("shifts"))
nav_btn_shifts.pack(fill="x", padx=6, pady=2, ipady=4)

tk.Label(sidebar, text="SPRÁVA", font=("Consolas", 8, "bold"), bg=BG_SIDEBAR, fg=TEXT_MUTED).pack(anchor="w", padx=14, pady=(16, 6))

nav_btn_svc = tk.Button(sidebar, text="🛵 Servis & Údržba", font=("Consolas", 10, "bold"), bg=BG_SIDEBAR, fg=TEXT_MUTED, relief="flat", anchor="w", padx=12, command=lambda: switch_view("svc"))
nav_btn_svc.pack(fill="x", padx=6, pady=2, ipady=4)

nav_btn_cfg = tk.Button(sidebar, text="⚙ Nastavení", font=("Consolas", 10, "bold"), bg=BG_SIDEBAR, fg=TEXT_MUTED, relief="flat", anchor="w", padx=12, command=lambda: switch_view("cfg"))
nav_btn_cfg.pack(fill="x", padx=6, pady=2, ipady=4)

sb_footer = tk.Frame(sidebar, bg=BG_SIDEBAR)
sb_footer.pack(side="bottom", fill="x", padx=6, pady=12)

lbl_shift_timer = tk.Label(sb_footer, text="00:00:00", font=("Consolas", 12, "bold"), bg=BG_SIDEBAR, fg=TEXT_WHITE)
lbl_shift_timer.pack(pady=2)

btn_shift = tk.Button(sb_footer, text="▶ START SMĚNY", font=("Consolas", 9, "bold"), bg=BG_APP, fg=ACCENT_CYAN, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=toggle_shift)
btn_shift.pack(fill="x", ipady=3)

# ================= CONTENT AREA =================
content = tk.Frame(body, bg=BG_APP)
content.pack(side="right", fill="both", expand=True, padx=12, pady=12)

style = ttk.Style()
style.theme_use("clam")
style.configure("Treeview", background=BG_CARD, foreground=TEXT_WHITE, fieldbackground=BG_CARD, borderwidth=0, font=("Consolas", 9))
style.configure("Treeview.Heading", background=BG_SIDEBAR, foreground=TEXT_MUTED, font=("Consolas", 9, "bold"))
style.map("Treeview", background=[("selected", BORDER_HIGHLIGHT)])

# ----- VIEW 1: DASHBOARD -----
view_dashboard = tk.Frame(content, bg=BG_APP)
view_dashboard.pack(fill="both", expand=True)

metrics_grid = tk.Frame(view_dashboard, bg=BG_APP)
metrics_grid.pack(fill="x", pady=(0, 12))

for col in range(3):
    metrics_grid.columnconfigure(col, weight=1)

def create_card(parent, title, val_text, val_color, row, col):
    card = tk.Frame(parent, bg=BG_CARD, highlightthickness=1, highlightbackground=BORDER_COLOR)
    card.grid(row=row, column=col, sticky="nsew", padx=4, pady=4)
    tk.Label(card, text=title, font=("Consolas", 8, "bold"), bg=BG_CARD, fg=TEXT_MUTED).pack(anchor="w", padx=10, pady=(8, 2))
    lbl = tk.Label(card, text=val_text, font=("Consolas", 14, "bold"), bg=BG_CARD, fg=val_color)
    lbl.pack(anchor="w", padx=10, pady=(0, 8))
    return lbl

card_val_profit = create_card(metrics_grid, "ČISTÝ ZISK", "+0 Kč", ACCENT_GREEN, 0, 0)
card_val_dyska = create_card(metrics_grid, "CELKEM DÝŠKA", "+0 Kč", ACCENT_GREEN, 0, 1)
card_val_palivo = create_card(metrics_grid, "CELKEM PALIVO", "-0 Kč", ACCENT_ORANGE, 0, 2)

card_val_km = create_card(metrics_grid, "CELKOVÝ NÁJEZD", "0 km", ACCENT_BLUE, 1, 0)
card_val_drops = create_card(metrics_grid, "POČET OBJEDNÁVEK", "0", ACCENT_CYAN, 1, 1)
card_val_avg = create_card(metrics_grid, "PRŮMĚR / OBJEDNÁVKA", "0.0 Kč", TEXT_WHITE, 1, 2)

log_box = tk.Frame(view_dashboard, bg=BG_CARD, highlightthickness=1, highlightbackground=BORDER_COLOR)
log_box.pack(fill="both", expand=True, pady=4)

tk.Label(log_box, text="RYCHLÝ ZÁPIS HODNOT", font=("Consolas", 10, "bold"), bg=BG_CARD, fg=TEXT_WHITE).pack(anchor="w", padx=14, pady=(12, 6))

type_selector = tk.Frame(log_box, bg=BG_CARD)
type_selector.pack(fill="x", padx=14, pady=4)

btn_type_dysko = tk.Button(type_selector, text="💰 + DÝŠKO", font=("Consolas", 10, "bold"), bg=BG_CARD, fg=ACCENT_GREEN, relief="flat", highlightthickness=1, highlightbackground=BORDER_HIGHLIGHT, command=lambda: nastav_typ("DYSKO"))
btn_type_dysko.pack(side="left", fill="x", expand=True, padx=(0, 2), ipady=4)

btn_type_palivo = tk.Button(type_selector, text="⛽ - PALIVO", font=("Consolas", 10, "bold"), bg=BG_APP, fg=TEXT_MUTED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=lambda: nastav_typ("PALIVO"))
btn_type_palivo.pack(side="left", fill="x", expand=True, padx=2, ipady=4)

btn_type_km = tk.Button(type_selector, text="🛵 🚗 KM / JÍZDA", font=("Consolas", 10, "bold"), bg=BG_APP, fg=TEXT_MUTED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=lambda: nastav_typ("KM"))
btn_type_km.pack(side="left", fill="x", expand=True, padx=(2, 0), ipady=4)

input_label = tk.Label(log_box, text="ZADEJ ČÁSTKU DÝŠKA (KČ):", font=("Consolas", 9, "bold"), bg=BG_CARD, fg=TEXT_MUTED)
input_label.pack(anchor="w", padx=14, pady=(12, 2))

entry_box = tk.Frame(log_box, bg=BORDER_COLOR, highlightthickness=1, highlightbackground=BORDER_HIGHLIGHT)
entry_box.pack(fill="x", padx=14, pady=4)

entry_val = tk.Entry(entry_box, font=("Consolas", 16), bg=BG_INPUT, fg=TEXT_WHITE, insertbackground=ACCENT_GREEN, relief="flat")
entry_val.pack(fill="x", padx=8, pady=8)
entry_val.focus()
entry_val.bind("<Return>", execute_log)

btn_submit = tk.Button(log_box, text="ZAPSAT DÝŠKO [Enter]", font=("Consolas", 11, "bold"), bg=BG_APP, fg=ACCENT_GREEN, relief="flat", highlightthickness=1, highlightbackground=BORDER_HIGHLIGHT, cursor="hand2", command=execute_log)
btn_submit.pack(fill="x", padx=14, pady=12, ipady=6)

status_label = tk.Label(log_box, text="[*] Systém připraven.", font=("Consolas", 9), bg=BG_CARD, fg=TEXT_MUTED)
status_label.pack(anchor="w", padx=14, pady=(0, 8))

# ----- VIEW 2: HISTORY (MODERN SINGLE VIEW WITH FILTER BAR) -----
view_history = tk.Frame(content, bg=BG_APP)

# Category Filter Bar + Search Bar
hist_header = tk.Frame(view_history, bg=BG_CARD, highlightthickness=1, highlightbackground=BORDER_COLOR)
hist_header.pack(fill="x", pady=(0, 8), padx=2, ipady=4)

# Filter Tabs inside History
filter_tabs = tk.Frame(hist_header, bg=BG_CARD)
filter_tabs.pack(side="left", padx=8)

btn_flt_all = tk.Button(filter_tabs, text="VŠECHNO", font=("Consolas", 8, "bold"), bg=BG_CARD, fg=TEXT_WHITE, relief="flat", highlightthickness=1, highlightbackground=BORDER_HIGHLIGHT, command=lambda: set_history_filter("ALL"))
btn_flt_all.pack(side="left", padx=2, ipady=2)

btn_flt_dyska = tk.Button(filter_tabs, text="💰 DÝŠKA", font=("Consolas", 8, "bold"), bg=BG_APP, fg=TEXT_MUTED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=lambda: set_history_filter("dyska"))
btn_flt_dyska.pack(side="left", padx=2, ipady=2)

btn_flt_palivo = tk.Button(filter_tabs, text="⛽ PALIVO", font=("Consolas", 8, "bold"), bg=BG_APP, fg=TEXT_MUTED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=lambda: set_history_filter("palivo"))
btn_flt_palivo.pack(side="left", padx=2, ipady=2)

btn_flt_km = tk.Button(filter_tabs, text="🛵 KILOMETRY", font=("Consolas", 8, "bold"), bg=BG_APP, fg=TEXT_MUTED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=lambda: set_history_filter("km"))
btn_flt_km.pack(side="left", padx=2, ipady=2)

# Search Input
search_container = tk.Frame(hist_header, bg=BG_CARD)
search_container.pack(side="left", fill="x", expand=True, padx=12)

tk.Label(search_container, text="🔍", font=("Consolas", 9), bg=BG_CARD, fg=TEXT_MUTED).pack(side="left", padx=(0, 4))
entry_search = tk.Entry(search_container, font=("Consolas", 10), bg=BG_INPUT, fg=TEXT_WHITE, insertbackground=ACCENT_GREEN, relief="flat")
entry_search.pack(side="left", fill="x", expand=True, ipady=2)
entry_search.bind("<KeyRelease>", lambda e: refresh_ui())

tk.Button(search_container, text="✕", font=("Consolas", 8, "bold"), bg=BG_CARD, fg=TEXT_MUTED, relief="flat", command=lambda: [entry_search.delete(0, tk.END), refresh_ui()]).pack(side="left", padx=2)

# Action Buttons
tk.Button(hist_header, text="🗑 Smazat vybrané", font=("Consolas", 8, "bold"), bg=BG_APP, fg=ERR_RED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=delete_selected_history).pack(side="right", padx=6, ipady=2)
tk.Button(hist_header, text="📥 Export CSV", font=("Consolas", 8, "bold"), bg=BG_APP, fg=ACCENT_CYAN, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=export_csv).pack(side="right", padx=2, ipady=2)

# Treeview Panel
tree_frame = tk.Frame(view_history, bg=BORDER_COLOR, highlightthickness=1, highlightbackground=BORDER_COLOR)
tree_frame.pack(fill="both", expand=True, padx=2)

tree_scroll = tk.Scrollbar(tree_frame, bg=BG_SIDEBAR)
tree_scroll.pack(side="right", fill="y")

tree_history = ttk.Treeview(tree_frame, columns=("typ", "cas", "hodnota"), show="headings", selectmode="extended", yscrollcommand=tree_scroll.set)
tree_history.heading("typ", text="TYP ZÁZNAMU")
tree_history.heading("cas", text="DATUM A ČAS")
tree_history.heading("hodnota", text="HODNOTA / ČÁSTKA")

tree_history.column("typ", width=180, anchor="w")
tree_history.column("cas", width=220, anchor="center")
tree_history.column("hodnota", width=220, anchor="e")

tree_history.pack(fill="both", expand=True)
tree_scroll.config(command=tree_history.yview)
tree_history.bind("<Button-1>", toggle_tree_selection)

tree_history.tag_configure("green", foreground=ACCENT_GREEN)
tree_history.tag_configure("orange", foreground=ACCENT_ORANGE)
tree_history.tag_configure("blue", foreground=ACCENT_BLUE)

# Bottom Bar History
hist_footer = tk.Frame(view_history, bg=BG_APP)
hist_footer.pack(fill="x", pady=(6, 0))
tk.Button(hist_footer, text="💣 Smazat celou historii záznamů", font=("Consolas", 8, "bold"), bg=BG_CARD, fg=ERR_RED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=clear_entire_history).pack(side="left", padx=2, ipady=2)

# ----- VIEW 3: SHIFTS HISTORY -----
view_shifts = tk.Frame(content, bg=BG_APP)

shifts_actions = tk.Frame(view_shifts, bg=BG_APP)
shifts_actions.pack(fill="x", pady=(0, 6))

tk.Button(shifts_actions, text="🗑 Smazat vybrané směny", font=("Consolas", 9, "bold"), bg=BG_CARD, fg=ERR_RED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=delete_selected_shifts).pack(side="left", padx=2, ipady=3)
tk.Button(shifts_actions, text="💣 Smazat celou historii směn", font=("Consolas", 9, "bold"), bg=BG_CARD, fg=ERR_RED, relief="flat", highlightthickness=1, highlightbackground=BORDER_COLOR, command=clear_all_shifts).pack(side="left", padx=2, ipady=3)

tree_shifts_frame = tk.Frame(view_shifts, bg=BORDER_COLOR, highlightthickness=1, highlightbackground=BORDER_COLOR)
tree_shifts_frame.pack(fill="both", expand=True)

tree_shifts_scroll = tk.Scrollbar(tree_shifts_frame, bg=BG_SIDEBAR)
tree_shifts_scroll.pack(side="right", fill="y")

tree_shifts = ttk.Treeview(tree_shifts_frame, columns=("datum", "trvani", "zisk", "hodinovka", "dropy", "km"), show="headings", selectmode="extended", yscrollcommand=tree_shifts_scroll.set)
tree_shifts.heading("datum", text="DATUM ZAČÁTKU")
tree_shifts.heading("trvani", text="ČAS SMĚNY")
tree_shifts.heading("zisk", text="ČISTÝ ZISK")
tree_shifts.heading("hodinovka", text="HODINOVKA")
tree_shifts.heading("dropy", text="DROPY")
tree_shifts.heading("km", text="NÁJEZD")

tree_shifts.column("datum", width=150, anchor="w")
tree_shifts.column("trvani", width=100, anchor="center")
tree_shifts.column("zisk", width=110, anchor="e")
tree_shifts.column("hodinovka", width=110, anchor="e")
tree_shifts.column("dropy", width=70, anchor="center")
tree_shifts.column("km", width=90, anchor="e")

tree_shifts.pack(fill="both", expand=True)
tree_shifts_scroll.config(command=tree_shifts.yview)
tree_shifts.bind("<Button-1>", toggle_shifts_selection)

tree_shifts.tag_configure("profit_pos", foreground=ACCENT_GREEN)
tree_shifts.tag_configure("profit_neg", foreground=ERR_RED)

# ----- VIEW 4: SERVICE -----
view_service = tk.Frame(content, bg=BG_APP)

svc_card = tk.Frame(view_service, bg=BG_CARD, highlightthickness=1, highlightbackground=BORDER_COLOR)
svc_card.pack(fill="both", expand=True, pady=4)

svc_header_title = tk.Label(svc_card, text="SERVISNÍ DENÍK // VOZIDLO", font=("Consolas", 11, "bold"), bg=BG_CARD, fg=TEXT_WHITE)
svc_header_title.pack(anchor="w", padx=16, pady=(16, 4))
tk.Label(svc_card, text="Systém automaticky odečítá ujeté kilometry od servisních intervalů.", font=("Consolas", 8), bg=BG_CARD, fg=TEXT_MUTED).pack(anchor="w", padx=16, pady=(0, 16))

def create_svc_item(parent, title, reset_func):
    box = tk.Frame(parent, bg=BG_APP, highlightthickness=1, highlightbackground=BORDER_COLOR)
    box.pack(fill="x", padx=16, pady=6, ipady=4)
    
    info = tk.Frame(box, bg=BG_APP)
    info.pack(side="left", padx=12, pady=8)
    tk.Label(info, text=title, font=("Consolas", 10, "bold"), bg=BG_APP, fg=TEXT_WHITE).pack(anchor="w")
    desc_lbl = tk.Label(info, text="", font=("Consolas", 8), bg=BG_APP, fg=TEXT_MUTED)
    desc_lbl.pack(anchor="w")

    btn = tk.Button(box, text="✔ RESETOVAT", font=("Consolas", 8, "bold"), bg=BG_CARD, fg=ACCENT_CYAN, relief="flat", highlightthickness=1, highlightbackground=BORDER_HIGHLIGHT, command=reset_func)
    btn.pack(side="right", padx=12)

    val_lbl = tk.Label(box, text="0 km", font=("Consolas", 12, "bold"), bg=BG_APP, fg=ACCENT_GREEN)
    val_lbl.pack(side="right", padx=16)
    return val_lbl, desc_lbl

val_svc_engine, lbl_desc_engine = create_svc_item(svc_card, "Motorový olej", lambda: reset_service("last_engine_oil_km", "Motorový olej"))
val_svc_gear, lbl_desc_gear = create_svc_item(svc_card, "Převodový olej", lambda: reset_service("last_gear_oil_km", "Převodový olej"))
val_svc_spark, lbl_desc_spark = create_svc_item(svc_card, "Zapalovací svíčka & Vzduchový filtr", lambda: reset_service("last_spark_plug_km", "Svíčka / filtr"))

# ----- VIEW 5: SETTINGS -----
view_settings = tk.Frame(content, bg=BG_APP)

cfg_card = tk.Frame(view_settings, bg=BG_CARD, highlightthickness=1, highlightbackground=BORDER_COLOR)
cfg_card.pack(fill="both", expand=True, pady=4)

tk.Label(cfg_card, text="SPRÁVA PROFILŮ VOZIDLA & INTERVALŮ", font=("Consolas", 11, "bold"), bg=BG_CARD, fg=TEXT_WHITE).pack(anchor="w", padx=16, pady=(16, 4))

top_cfg_bar = tk.Frame(cfg_card, bg=BG_CARD)
top_cfg_bar.pack(fill="x", padx=16, pady=(4, 8))

tk.Label(top_cfg_bar, text="Vyber profil vozidla:", font=("Consolas", 9, "bold"), bg=BG_CARD, fg=TEXT_MUTED).pack(side="left")
tk.Button(top_cfg_bar, text="[ + VYTVOŘIT NOVÝ PROFIL ]", font=("Consolas", 8, "bold"), bg=BG_APP, fg=ACCENT_CYAN, relief="flat", highlightthickness=1, highlightbackground=BORDER_HIGHLIGHT, command=create_new_custom_profile).pack(side="right")

preset_combo = ttk.Combobox(cfg_card, state="readonly", font=("Consolas", 10))
preset_combo.pack(fill="x", padx=16, pady=4)
preset_combo.bind("<<ComboboxSelected>>", on_preset_select)

form_intervals = tk.Frame(cfg_card, bg=BG_CARD)
form_intervals.pack(fill="x", padx=16, pady=12)
form_intervals.columnconfigure(1, weight=1)

tk.Label(form_intervals, text="Motorový olej (interval km):", font=("Consolas", 9, "bold"), bg=BG_CARD, fg=TEXT_WHITE).grid(row=0, column=0, sticky="w", pady=6)
entry_cfg_engine = tk.Entry(form_intervals, font=("Consolas", 10), bg=BG_INPUT, fg=ACCENT_GREEN, insertbackground=ACCENT_GREEN)
entry_cfg_engine.grid(row=0, column=1, sticky="ew", padx=(12, 0), pady=6)

tk.Label(form_intervals, text="Převodový olej (interval km):", font=("Consolas", 9, "bold"), bg=BG_CARD, fg=TEXT_WHITE).grid(row=1, column=0, sticky="w", pady=6)
entry_cfg_gear = tk.Entry(form_intervals, font=("Consolas", 10), bg=BG_INPUT, fg=ACCENT_ORANGE, insertbackground=ACCENT_ORANGE)
entry_cfg_gear.grid(row=1, column=1, sticky="ew", padx=(12, 0), pady=6)

tk.Label(form_intervals, text="Svíčka & Filtr (interval km):", font=("Consolas", 9, "bold"), bg=BG_CARD, fg=TEXT_WHITE).grid(row=2, column=0, sticky="w", pady=6)
entry_cfg_spark = tk.Entry(form_intervals, font=("Consolas", 10), bg=BG_INPUT, fg=ACCENT_CYAN, insertbackground=ACCENT_CYAN)
entry_cfg_spark.grid(row=2, column=1, sticky="ew", padx=(12, 0), pady=6)

btn_save_p = tk.Button(cfg_card, text="[ ULOŽIT INTERVALY & AKTIVOVAT PROFIL ]", font=("Consolas", 10, "bold"), bg=BG_APP, fg=ACCENT_PURPLE, relief="flat", highlightthickness=1, highlightbackground=BORDER_HIGHLIGHT, command=save_cfg_profile)
btn_save_p.pack(fill="x", padx=16, pady=16, ipady=6)

cfg = load_settings()
preset_combo["values"] = list(cfg["presets"].keys())
preset_combo.set(cfg.get("active_preset", list(cfg["presets"].keys())[0]))
on_preset_select()

# Grip
grip = tk.Label(app_wrapper, text="◢", font=("Arial", 8), bg=BG_APP, fg=TEXT_MUTED, cursor="size_nw_se")
grip.pack(anchor="se", padx=2, pady=0)
grip.bind("<Button-1>", start_resize)
grip.bind("<B1-Motion>", do_resize)

refresh_ui()
okno.mainloop()
{
    "dyska": [],
    "palivo": [],
    "km": [],
    "shifts": []
}
{
    "active_preset": "Maxon Matador 125cc (Skútr)",
    "presets": {
        "Maxon Matador 125cc (Skútr)": {
            "engine_oil_interval": 2500,
            "gear_oil_interval": 5000,
            "spark_plug_interval": 5000
        },
        "Univerzální Skútr 50cc 4T": {
            "engine_oil_interval": 2000,
            "gear_oil_interval": 4000,
            "spark_plug_interval": 4000
        },
        "Osobní auto (Benzín / Nafta)": {
            "engine_oil_interval": 10000,
            "gear_oil_interval": 60000,
            "spark_plug_interval": 30000
        }
    },
    "service_history": {
        "last_engine_oil_km": 0,
        "last_gear_oil_km": 0,
        "last_spark_plug_km": 0
    }
}
__pycache__/
*.pyc
courier_data.json
settings.json
*.csv
dist/
build/
*.spec
