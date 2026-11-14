require "import"
import "com.androlua.LuaDialog"
import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "android.widget.TextView"
import "android.widget.Button"
import "android.widget.EditText"
import "android.widget.ListView"
import "android.widget.ArrayAdapter"
import "android.widget.AdapterView"
import "android.widget.SeekBar"
import "android.widget.Spinner"
import "android.widget.Toast"
import "java.util.ArrayList"
import "android.text.TextWatcher"
import "android.view.KeyEvent"
import "android.os.Handler"
import "android.os.Looper"
import "android.os.HandlerThread"
import "android.media.MediaExtractor"
import "android.media.MediaCodec"
import "android.media.MediaPlayer"
import "android.media.AudioTrack"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.io.DataOutputStream"
import "java.util.Scanner"
import "java.net.URL"
import "java.nio.ByteOrder"
import "org.json.JSONObject"
import "android.view.View"
import "android.content.Intent"
import "android.net.Uri"
import "android.content.ClipData"

local ctx = activity or service or this
local ui
pcall(function()
  local looper = Looper.getMainLooper()
  if looper then ui = Handler(looper) end
end)
if not ui then
  pcall(function() ui = Handler() end)
end

local function kirimUI(fn, jeda)
  local r = Runnable({ run = fn })
  if ui then
    local ok, hasil = pcall(function()
      if jeda and jeda > 0 then return ui.postDelayed(r, jeda) end
      return ui.post(r)
    end)
    if ok and hasil then return true end
  end
  local target = activity or service
  if target then
    local ok = pcall(function() target.runOnUiThread(r) end)
    if ok then return true end
  end
  return false
end

DJL = DJL or {}
local NAMA_EKSTENSI = "Tools detector tempo dan chord"
local LAJU = 44100
local LAJU_AKOR = 11025
local BATAS_UNGGAH = 15 * 1024 * 1024
local BATAS_AUDO = 95 * 1024 * 1024
local LAMAN_KUNCI = "https://freqblog.com/music-api.html"
local LAMAN_KUNCI_AUDO = "https://audo.ai/keys"
local ALAMAT_AUDO = "https://audo.ai/api/try/key-bpm"
local NAMA_PENYEDIA = { freqblog = "FreqBlog", audo = "Audo AI" }
local ALFABET_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local INDEKS_B64 = {}
for i = 1, 64 do INDEKS_B64[string.byte(ALFABET_B64, i)] = i - 1 end
local NAMA_NADA = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local PROFIL_MAYOR = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
local PROFIL_MINOR = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }
local EKSTENSI = { mp3 = true, m4a = true, aac = true, wav = true, flac = true, ogg = true, opus = true }
local DAFTAR_BUNYI = { "cubase", "tiruan", "kayu", "klik", "bip" }
local NAMA_BUNYI = { cubase = "Cubase", tiruan = "Tiruan Cubase", kayu = "Kayu", klik = "Klik", bip = "Bip", sampel = "Sampel sendiri" }
local KUNCI_PENGATURAN = { "token", "tokenAudo", "penyedia", "folder", "bunyi", "birama", "volKlik", "volLagu", "sampel", "sampelNama", "sampelAksen", "sampelAksenNama", "favorit", "terakhir", "mulaiPutar", "studioProgresi", "studioTempo", "studioPola", "studioKetuk" }
local pengaturan = { token = "", tokenAudo = "", penyedia = "freqblog", folder = "/storage/emulated/0/Music;/storage/emulated/0/Download", bunyi = "cubase", birama = "4", volKlik = "80", volLagu = "80", sampel = "", sampelNama = "", sampelAksen = "", sampelAksenNama = "", favorit = "", terakhir = "", mulaiPutar = "awal", studioProgresi = "C,G,Am,F", studioTempo = "100", studioPola = "balok", studioKetuk = "4" }

local System = luajava.bindClass("java.lang.System")

pcall(function()
  if DJL.ht then DJL.ht.quit() end
end)
pcall(function()
  if DJL.htNet then DJL.htNet.quit() end
end)
local okPekerja = pcall(function()
  local ht = HandlerThread("DJL-kerja", 10)
  ht.start()
  DJL.ht = ht
  DJL.pekerja = Handler(ht.getLooper())
  local ht2 = HandlerThread("DJL-jaringan", 10)
  ht2.start()
  DJL.htNet = ht2
  DJL.pekerjaNet = Handler(ht2.getLooper())
end)
if not okPekerja then
  DJL.ht = nil
  DJL.htNet = nil
  DJL.pekerjaNet = nil
  DJL.pekerja = ui
end
local D = {}
local SM = {}
local MT = {}
local ps = nil
DJL.hentikanStudio = function() end

local menuUtama, menuLagu, menuAnalisis, menuHasil, menuPengaturan, menuRiwayat, menuSampel
local layarPemutar, layarPenyedia, layarSuara, tampilHasilAnalisis, pilihLagu, pemutarUtama

local tampilGalat
local ambilHasil

local function penelusur(e)
  local t = tostring(e)
  pcall(function()
    if debug and debug.traceback then t = t .. "\n" .. debug.traceback("", 2) end
  end)
  return t
end

local function aman(fn)
  return function(...)
    local n = select("#", ...)
    local argumen = { ... }
    local unp = table.unpack or unpack
    local ok, hasil = xpcall(function() return fn(unp(argumen, 1, n)) end, penelusur)
    if not ok then
      if tampilGalat then tampilGalat("Terjadi galat", hasil) end
      return nil
    end
    return hasil
  end
end

local function jalankanUI(fn)
  kirimUI(aman(fn))
end

local function tunda(ms, fn)
  kirimUI(aman(fn), ms)
end

local function toast(teks)
  jalankanUI(function()
    pcall(function()
      local s = tostring(teks)
      if DJL.toastTerakhir then pcall(function() DJL.toastTerakhir.cancel() end) end
      local t = Toast.makeText(ctx, s, #s > 60 and 1 or 0)
      DJL.toastTerakhir = t
      t.show()
    end)
  end)
end

local function latar(fn)
  local th = Thread(Runnable({ run = function()
    pcall(function() luajava.bindClass("android.os.Process").setThreadPriority(19) end)
    local ok, err = pcall(fn)
    if not ok then toast("Proses latar gagal: " .. tostring(err)) end
  end }))
  th.start()
end

local function napas()
  local co, utama = coroutine.running()
  if co == nil or utama == true then return end
  if (DJL.kunciYield or 0) > 0 then return end
  if os.clock() >= (DJL.batasIris or 0) then coroutine.yield() end
end

local function jamMs()
  return os.clock() * 1000
end

local function jeda(ms)
  local co, utama = coroutine.running()
  if co == nil or utama == true then
    pcall(function() Thread.sleep(ms) end)
    return
  end
  coroutine.yield("tunggu", ms)
end

local function lindungi(fn, ...)
  DJL.kunciYield = (DJL.kunciYield or 0) + 1
  local ok, a, b, c = pcall(fn, ...)
  DJL.kunciYield = DJL.kunciYield - 1
  return ok, a, b, c
end

local terapkanProgres

local function jalankanBertahap(tugas, selesai, jalur)
  local co = nil
  local irisan
  local function jadwalkan(tundaMs)
    local p = DJL.pekerja
    if jalur == "jaringan" and DJL.pekerjaNet then p = DJL.pekerjaNet end
    if p == nil then return end
    p.postDelayed(Runnable({ run = aman(irisan) }), tundaMs)
  end
  irisan = function()
    DJL.batasIris = os.clock() + 0.025
    if co == nil then co = coroutine.create(tugas) end
    local ok, a, b, c, d = coroutine.resume(co)
    if terapkanProgres then terapkanProgres() end
    if not ok then
      local rinci = tostring(a)
      pcall(function() rinci = debug.traceback(co, tostring(a)) end)
      jalankanUI(function() selesai(false, rinci) end)
    elseif coroutine.status(co) == "dead" then
      jalankanUI(function() selesai(true, a, b, c, d) end)
    elseif a == "tunggu" then
      jadwalkan(tonumber(b) or 14)
    else
      jadwalkan(14)
    end
  end
  jadwalkan(0)
end

local function tundaKunci(kunci, ms, fn)
  DJL.debounce = DJL.debounce or {}
  local lama = DJL.debounce[kunci]
  if lama and ui then pcall(function() ui.removeCallbacks(lama) end) end
  local r = Runnable({ run = function()
    DJL.debounce[kunci] = nil
    aman(fn)()
  end })
  DJL.debounce[kunci] = r
  kirimUI(function() r.run() end, ms)
end

local function larik(tipe, n)
  local Arr = luajava.bindClass("java.lang.reflect.Array")
  local kelas = luajava.bindClass("java.lang." .. tipe).TYPE
  return Arr.newInstance(kelas, n)
end

local function panjangLarik(a)
  local n = 0
  local ok = pcall(function() n = a.length end)
  if not ok or type(n) ~= "number" then
    pcall(function() n = #a end)
  end
  return n
end

local function buatJava(namaKelas, ...)
  local n = select("#", ...)
  local argumen = { ... }
  local unp = table.unpack or unpack
  local kelas = luajava.bindClass(namaKelas)
  local ok1, hasil = pcall(function() return kelas(unp(argumen, 1, n)) end)
  if ok1 and hasil ~= nil then return hasil end
  local ok2, obj = pcall(function()
    local KelasJ = luajava.bindClass("java.lang.Class")
    local RefArr = luajava.bindClass("java.lang.reflect.Array")
    local cls = KelasJ.forName(namaKelas)
    local objCls = KelasJ.forName("java.lang.Object")
    local daftar = cls.getConstructors()
    for i = 0, panjangLarik(daftar) - 1 do
      local c = daftar[i]
      local tipe = c.getParameterTypes()
      if panjangLarik(tipe) == n then
        local cocok = true
        for j = 0, n - 1 do
          local a = argumen[j + 1]
          local t = tipe[j]
          local okc, isi = pcall(function() return t.isInstance(a) end)
          if a == nil or not okc or not isi then
            cocok = false
            break
          end
        end
        if cocok then
          local arr = RefArr.newInstance(objCls, n)
          for j = 0, n - 1 do RefArr.set(arr, j, argumen[j + 1]) end
          return c.newInstance(arr)
        end
      end
    end
    error("konstruktor tidak ditemukan")
  end)
  if ok2 and obj ~= nil then return obj end
  error(namaKelas .. " gagal dibuat. Langsung: " .. tostring(hasil) .. ". Refleksi: " .. tostring(obj), 0)
end

local function angka(x, n)
  return (string.gsub(string.format("%." .. tostring(n) .. "f", x), "%.", ","))
end

local function pangkas(teks)
  local r = string.gsub(tostring(teks or ""), "^%s+", "")
  r = string.gsub(r, "%s+$", "")
  return r
end

local function bersihKunci(teks)
  return (string.gsub(tostring(teks or ""), "%s+", ""))
end

local function kunciValid(t)
  return #t >= 12 and string.match(t, "^[%w_%-]+$") ~= nil
end

local function salin(teks)
  local ok = pcall(function()
    local cm = ctx.getSystemService("clipboard")
    cm.setPrimaryClip(ClipData.newPlainText("teks", teks))
  end)
  if ok then toast("Disalin ke papan klip") else toast("Gagal menyalin") end
end

local function bacaClipboard()
  local teks = ""
  pcall(function()
    local cm = ctx.getSystemService("clipboard")
    local clip = cm.getPrimaryClip()
    if clip ~= nil and clip.getItemCount() > 0 then
      teks = tostring(clip.getItemAt(0).coerceToText(ctx))
    end
  end)
  return teks
end

local function bukaTautan(alamat)
  local ok = pcall(function()
    local i = Intent("android.intent.action.VIEW", Uri.parse(alamat))
    i.addFlags(268435456)
    ctx.startActivity(i)
  end)
  if not ok then
    salin(alamat)
    toast("Tautan disalin")
  end
end

local function pref()
  return ctx.getSharedPreferences("TempoKunciPrefs", 0)
end

local function simpanTeks(k, v)
  pcall(function() pref().edit().putString(k, v).apply() end)
end

local function hapusTeks(k)
  pcall(function() pref().edit().remove(k).apply() end)
end

local function bacaTeks(k)
  local v = nil
  pcall(function() v = pref().getString(k, nil) end)
  if v == nil then return nil end
  return tostring(v)
end

local function muatPengaturan()
  for _, k in ipairs(KUNCI_PENGATURAN) do
    pengaturan[k] = bacaTeks("set_" .. k) or pengaturan[k]
  end
  if string.sub(pengaturan.penyedia, 1, 4) == "audo" then pengaturan.penyedia = "audo" end
  if pengaturan.penyedia ~= "audo" then pengaturan.penyedia = "freqblog" end
end

local function simpanPengaturan()
  for _, k in ipairs(KUNCI_PENGATURAN) do
    simpanTeks("set_" .. k, pengaturan[k])
  end
end

local function serial(t)
  local baris = {}
  for k, v in pairs(t) do
    if k == "chord" and type(v) == "table" then
      local bagian = {}
      for _, c in ipairs(v) do
        bagian[#bagian + 1] = table.concat({
          tostring(c.nama or ""),
          string.format("%.3f", tonumber(c.mulai) or 0),
          string.format("%.3f", tonumber(c.akhir) or 0),
          string.format("%.3f", tonumber(c.skor) or 0),
          tostring(c.bass or ""),
          tostring(c.nada or ""),
          tostring(c.kualitas or "")
        }, "~")
      end
      baris[#baris + 1] = "chord=" .. table.concat(bagian, ";")
    elseif type(v) ~= "table" then
      baris[#baris + 1] = tostring(k) .. "=" .. tostring(v)
    end
  end
  return table.concat(baris, "\n")
end

local function urai(teks)
  local t = {}
  for k, v in string.gmatch(teks, "([%w_]+)=([^\n]*)") do
    if k == "chord" then
      local daftar = {}
      for bagian in string.gmatch(v, "[^;]+") do
        local kolom = {}
        for v in string.gmatch(bagian .. "~", "(.-)~") do kolom[#kolom + 1] = v end
        if kolom[1] and kolom[2] and kolom[3] then
          daftar[#daftar + 1] = {
            nama = kolom[1], mulai = tonumber(kolom[2]) or 0,
            akhir = tonumber(kolom[3]) or 0, skor = tonumber(kolom[4]) or 0,
            bass = kolom[5] or "", nada = kolom[6] or "", kualitas = kolom[7] or ""
          }
        end
      end
      t.chord = daftar
    else
      local n = tonumber(v)
      if n ~= nil then t[k] = n else t[k] = v end
    end
  end
  return t
end

local function dp(x)
  local d = 3
  pcall(function() d = ctx.getResources().getDisplayMetrics().density end)
  return math.floor(x * d + 0.5)
end

local function T(teks, ukuran)
  local t = TextView(ctx)
  t.setText(teks)
  t.setTextSize(ukuran or 16)
  t.setPadding(dp(8), dp(6), dp(8), dp(6))
  return t
end

local function B(teks, fn)
  local b = Button(ctx)
  b.setText(teks)
  b.setAllCaps(false)
  local aksi = aman(fn)
  b.setOnClickListener(View.OnClickListener({ onClick = function() aksi() end }))
  return b
end

local function E(petunjuk, nilai, angkaSaja)
  local e = EditText(ctx)
  e.setHint(petunjuk)
  e.setSingleLine(true)
  if angkaSaja then e.setInputType(12290) end
  if nilai and nilai ~= "" then e.setText(tostring(nilai)) end
  return e
end

local function dialogBaru(judul)
  local d = LuaDialog(ctx)
  if judul then d.setTitle(judul) end
  return d
end

local function bukaDialog(d)
  local lama = DJL.dlg
  DJL.dlg = d
  if lama then pcall(function() lama.dismiss() end) end
  d.show()
end

local function tutupDialog()
  local lama = DJL.dlg
  DJL.dlg = nil
  if lama then pcall(function() lama.dismiss() end) end
end

local function susunKolom(...)
  local L = LinearLayout(ctx)
  L.setOrientation(1)
  L.setPadding(dp(12), dp(8), dp(12), dp(8))
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v then L.addView(v) end
  end
  local sv = ScrollView(ctx)
  sv.addView(L)
  return sv
end

local function layarForm(judul, kembali, ...)
  local d = dialogBaru(judul)
  d.setView(susunKolom(...))
  if kembali then d.setOnCancelListener(aman(function() kembali() end)) end
  bukaDialog(d)
  return d
end

local function layarDaftar(opsi)
  local d = dialogBaru(opsi.judul)
  local isi = LinearLayout(ctx)
  isi.setOrientation(1)
  isi.setPadding(dp(8), dp(4), dp(8), dp(4))
  if opsi.atas then isi.addView(opsi.atas) end
  local arr = ArrayList()
  for _, v in ipairs(opsi.butir) do arr.add(v) end
  local lv = ListView(ctx)
  lv.setAdapter(ArrayAdapter(ctx, android.R.layout.simple_list_item_1, arr))
  local pil = aman(function(p) opsi.pilih(p) end)
  lv.setOnItemClickListener(AdapterView.OnItemClickListener({
    onItemClick = function(a, v, p, id) pil(p + 1) end }))
  isi.addView(lv, LinearLayout.LayoutParams(-1, -2, 1.0))
  d.setView(isi)
  local kembali = opsi.kembali
  local kem = aman(function() if kembali then kembali() end end)
  d.setButton(opsi.labelKembali or "Kembali", kem)
  d.setOnCancelListener(kem)
  bukaDialog(d)
  return d
end

local function dialogPesan(judul, pesan, tombol, kembali)
  local d = dialogBaru(judul)
  d.setMessage(pesan)
  local t1, t2, t3 = tombol[1], tombol[2], tombol[3]
  if t1 then d.setButton(t1[1], aman(function() if t1[2] then t1[2]() end end)) end
  if t2 then d.setButton2(t2[1], aman(function() if t2[2] then t2[2]() end end)) end
  if t3 then d.setButton3(t3[1], aman(function() if t3[2] then t3[2]() end end)) end
  if kembali then d.setOnCancelListener(aman(function() kembali() end)) end
  bukaDialog(d)
  return d
end

tampilGalat = function(judul, galat, lanjut)
  local teks = tostring(galat)
  local function tampil()
    pcall(function()
      DJL.sibuk = false
      dialogPesan(judul, teks, {
        { "Tutup", function() if lanjut then lanjut() end end },
        { "Salin galat", function()
          salin(teks)
          if lanjut then lanjut() end
        end } }, function() if lanjut then lanjut() end end)
    end)
  end
  if not kirimUI(tampil) then
    pcall(function()
      Toast.makeText(ctx, teks, Toast.LENGTH_LONG).show()
    end)
  end
end

local function dialogIsian(cfg)
  local d = dialogBaru(cfg.judul)
  local edit = E(cfg.hint or "", cfg.awal, cfg.angka)
  local tampilanPesan = nil
  if cfg.pesan then tampilanPesan = T(cfg.pesan, 15) end
  d.setView(susunKolom(tampilanPesan, edit))
  d.setButton(cfg.ok or "Simpan", aman(function() cfg.simpan(tostring(edit.getText())) end))
  d.setButton2("Batal", aman(function() if cfg.batal then cfg.batal() end end))
  if cfg.netral then d.setButton3(cfg.netral[1], aman(function() cfg.netral[2](tostring(edit.getText())) end)) end
  d.setOnCancelListener(aman(function() if cfg.batal then cfg.batal() end end))
  bukaDialog(d)
  return d
end

local function dialogAngka(judul, pesan, awal, pakai, kembali)
  dialogIsian({
    judul = judul,
    pesan = pesan,
    angka = true,
    awal = awal,
    hint = "Contoh: 120,5",
    ok = "Pakai",
    simpan = function(teks)
      local t = string.gsub(pangkas(teks), ",", ".")
      local num = tonumber(t)
      if num then
        pakai(num)
      else
        toast("Angka tidak valid")
        dialogAngka(judul, pesan, awal, pakai, kembali)
      end
    end,
    batal = kembali })
end

local function buatSpinner(daftar, awal, saatPilih)
  local sp = Spinner(ctx)
  local arr = ArrayList()
  for _, v in ipairs(daftar) do arr.add(v) end
  sp.setAdapter(ArrayAdapter(ctx, android.R.layout.simple_spinner_item, arr))
  sp.setSelection(awal - 1)
  if saatPilih then
    sp.setOnItemSelectedListener(AdapterView.OnItemSelectedListener({
      onItemSelected = function(a, v, p, id) saatPilih(p + 1) end,
      onNothingSelected = function(a) end }))
  end
  return sp
end

local function buatSlider(o)
  local langkah = o.langkah or 1
  local n = math.floor((o.max - o.min) / langkah + 0.5)
  local tv = T("", 16)
  local sb = SeekBar(ctx)
  sb.setMax(n)
  local nilai = o.nilai
  local abaikan = false
  local function segarkan()
    local teks = o.label(nilai)
    tv.setText(teks)
    pcall(function() sb.setContentDescription(teks) end)
  end
  local function setNilai(v)
    nilai = v
    local p = math.floor((v - o.min) / langkah + 0.5)
    if p < 0 then p = 0 elseif p > n then p = n end
    abaikan = true
    sb.setProgress(p)
    abaikan = false
    segarkan()
  end
  sb.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener({
    onProgressChanged = function(s, p, dariPengguna)
      if abaikan then return end
      nilai = o.min + math.floor(p) * langkah
      segarkan()
      if o.saatUbah then o.saatUbah(nilai) end
    end,
    onStartTrackingTouch = function(s) end,
    onStopTrackingTouch = function(s) if o.saatLepas then o.saatLepas(nilai) end end }))
  setNilai(o.nilai)
  local kol = LinearLayout(ctx)
  kol.setOrientation(1)
  kol.addView(tv)
  kol.addView(sb)
  return { view = kol, setNilai = setNilai, ambil = function() return nilai end }
end

local function bacaTanggapan(conn)
  local kode = conn.getResponseCode()
  local aliran
  if kode >= 400 then aliran = conn.getErrorStream() else aliran = conn.getInputStream() end
  local isi = ""
  if aliran then
    local sc = buatJava("java.util.Scanner", aliran, "UTF-8")
    sc.useDelimiter("\\A")
    if sc.hasNext() then isi = tostring(sc.next()) end
    sc.close()
  end
  conn.disconnect()
  return kode, isi
end

local function namaKunci(pc, mode)
  return NAMA_NADA[pc + 1] .. (mode == 1 and " mayor" or " minor")
end

local function uraiKunci(teks)
  local t = string.gsub(tostring(teks), "\226\153\175", "#")
  t = string.gsub(t, "\226\153\173", "b")
  local n, md = string.match(t, "^([A-Ga-g][#b]?)[%s%-]*(%a+)")
  if not n then return nil end
  local peta = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
  local pc = peta[string.upper(string.sub(n, 1, 1))]
  local ak = string.sub(n, 2, 2)
  if ak == "#" then pc = pc + 1 elseif ak == "b" then pc = pc - 1 end
  pc = pc % 12
  local mode = 1
  if string.lower(string.sub(md, 1, 3)) == "min" then mode = 0 end
  return pc, mode
end

local idLagu

local function ambilTranspose(item)
  return tonumber(bacaTeks("trans_" .. idLagu(item))) or 0
end

local function namaKunciGeser(pc, mode, geser)
  return namaKunci((pc + (geser or 0)) % 12, mode)
end

local function geserNamaNada(teks, geser)
  if not teks or teks == "" or not geser or geser == 0 then return teks or "" end
  local hasil = tostring(teks)
  local peta = { C = 0, ["C#"] = 1, D = 2, ["D#"] = 3, E = 4, F = 5, ["F#"] = 6, G = 7, ["G#"] = 8, A = 9, ["A#"] = 10, B = 11 }
  local function satu(n)
    local pc = peta[n]
    if pc == nil then return n end
    return NAMA_NADA[((pc + geser) % 12) + 1]
  end
  hasil = string.gsub(hasil, "([A-G]#?)([^A-Za-z#])", function(n, ekor) return satu(n) .. ekor end)
  hasil = string.gsub(hasil, "([A-G]#?)$", function(n) return satu(n) end)
  return hasil
end

local function geserNamaChord(teks, geser)
  if not teks or teks == "" or not geser or geser == 0 then return teks or "" end
  local akar, sisa = string.match(tostring(teks), "^([A-G]#?)(.*)$")
  if not akar then return tostring(teks) end
  local baru = geserNamaNada(akar, geser) .. sisa
  return string.gsub(baru, "/([A-G]#?)", function(bass) return "/" .. geserNamaNada(bass, geser) end)
end

local function dasarTranspose(item)
  local h = ambilHasil(item)
  if h.off and h.off.pc1 ~= nil then return h.off.pc1, h.off.mode1 or 0 end
  if h.on then
    local pc, md = uraiKunci(h.on.kunci)
    if pc ~= nil then return pc, md end
  end
  if h.peta then
    for _, b in ipairs(h.peta) do if b.pc ~= nil then return b.pc, b.mode or 0 end end
  end
  return nil, nil
end

local function menuTranspose(item, kembali)
  local pc, mode = dasarTranspose(item)
  if pc == nil then
    toast("Nada dasar belum tersedia. Jalankan analisis nada terlebih dahulu.")
    if kembali then kembali() end
    return
  end
  local geser = ambilTranspose(item)
  local butir, aksi = {}, {}
  butir[#butir + 1] = "Tampilan sekarang: " .. namaKunciGeser(pc, mode, geser)
  aksi[#aksi + 1] = function() menuTranspose(item, kembali) end
  butir[#butir + 1] = "Kembalikan ke nada asli: " .. namaKunci(pc, mode)
  aksi[#aksi + 1] = function()
    simpanTeks("trans_" .. idLagu(item), "0")
    toast("Tampilan dikembalikan ke nada asli. Audio tidak berubah.")
    if kembali then kembali() else menuTranspose(item, kembali) end
  end
  for i = 0, 11 do
    local target = (pc + i) % 12
    local selisih = (target - pc) % 12
    local nama = namaKunci(target, mode)
    butir[#butir + 1] = "Tampilkan sebagai " .. nama
    aksi[#aksi + 1] = function()
      simpanTeks("trans_" .. idLagu(item), tostring(selisih))
      toast("Tampilan nada diubah menjadi " .. nama .. ". Audio tetap asli.")
      if kembali then kembali() else menuTranspose(item, kembali) end
    end
  end
  layarDaftar({
    judul = "Transpose tampilan nada",
    butir = butir,
    pilih = function(i) aksi[i]() end,
    kembali = function() if kembali then kembali() else menuHasil(item) end end })
end

idLagu = function(item)
  return item.nama .. "_" .. tostring(item.ukuran)
end

local function waktuTeks(ms)
  local d = math.floor(ms / 1000 + 0.5)
  return tostring(math.floor(d / 60)) .. ":" .. string.format("%02d", d % 60)
end

local function simpanPeta(id, peta)
  local baris = {}
  for _, b in ipairs(peta) do
    baris[#baris + 1] = table.concat({
      b.tipe,
      string.format("%d", math.floor(b.mulaiMs + 0.5)),
      string.format("%d", math.floor(b.akhirMs + 0.5)),
      string.format("%.4f", b.bpm),
      string.format("%.4f", b.bpm2 or b.bpm),
      string.format("%d", math.floor((b.t0Ms or b.mulaiMs) + 0.5)),
      tostring(b.pc or -1),
      tostring(b.mode or 0),
      string.format("%.3f", b.skor or 0) }, "\t")
  end
  simpanTeks("peta_" .. id, table.concat(baris, "\n"))
end

local function bacaPeta(id)
  local teks = bacaTeks("peta_" .. id)
  if not teks then return nil end
  local peta = {}
  for baris in string.gmatch(teks, "[^\n]+") do
    local f = {}
    for v in string.gmatch(baris, "[^\t]+") do f[#f + 1] = v end
    if #f >= 9 then
      local pc = tonumber(f[7])
      if pc and pc < 0 then pc = nil end
      peta[#peta + 1] = { tipe = f[1], mulaiMs = tonumber(f[2]), akhirMs = tonumber(f[3]), bpm = tonumber(f[4]), bpm2 = tonumber(f[5]), t0Ms = tonumber(f[6]), pc = pc, mode = tonumber(f[8]), skor = tonumber(f[9]) }
    end
  end
  if #peta == 0 then return nil end
  return peta
end

ambilHasil = function(item)
  local id = idLagu(item)
  local t = {}
  local pt = bacaPeta(id)
  if pt then t.peta = pt end
  local a = bacaTeks("off_" .. id)
  if a then t.off = urai(a) end
  local b = bacaTeks("on_" .. id)
  if b then t.on = urai(b) end
  local f = bacaTeks("fix_" .. id)
  if f then t.fix = tonumber(f) end
  return t
end

local function bersihkanSD()
  local sd = DJL.sd
  DJL.sd = nil
  if sd then
    if sd.codec then
      pcall(function() sd.codec.stop() end)
      pcall(function() sd.codec.release() end)
    end
    if sd.ext then pcall(function() sd.ext.release() end) end
  end
end

local function tambahItem(daftar, lihat, path, ukuran)
  if lihat[path] then return end
  local ekst = string.lower(string.match(path, "%.(%w+)$") or "")
  if not EKSTENSI[ekst] then return end
  if ukuran < 100000 then return end
  lihat[path] = true
  local nama = string.match(path, "([^/]+)$") or path
  local folder = string.match(path, "^(.*)/[^/]*$") or ""
  daftar[#daftar + 1] = { nama = nama, path = path, ukuran = ukuran, folder = folder, nl = string.lower(nama) }
end

local function catatGalat(g, err)
  g.n = g.n + 1
  if not g.pertama then g.pertama = tostring(err) end
end

local function pindaiMediaStore(daftar, lihat, g)
  local ok, c = pcall(function()
    local Media = luajava.bindClass("android.provider.MediaStore$Audio$Media")
    local Arr = luajava.bindClass("java.lang.reflect.Array")
    local kolom = Arr.newInstance(luajava.bindClass("java.lang.String"), 3)
    Arr.set(kolom, 0, "_data")
    Arr.set(kolom, 1, "_size")
    Arr.set(kolom, 2, "duration")
    return ctx.getContentResolver().query(Media.EXTERNAL_CONTENT_URI, kolom, nil, nil, "date_added DESC")
  end)
  if not ok then
    catatGalat(g, "Kueri MediaStore gagal: " .. tostring(c))
    return
  end
  if c == nil then return end
  while #daftar < 6000 and g.n <= 50 do
    local ada = false
    local ok1, e1 = pcall(function() ada = c.moveToNext() end)
    if not ok1 then
      catatGalat(g, "MediaStore moveToNext gagal: " .. tostring(e1))
      break
    end
    if not ada then break end
    local ok2, e2 = pcall(function()
      local p = c.getString(0)
      local ukuran = c.getLong(1)
      local dur = c.getLong(2)
      if p ~= nil and (dur == 0 or dur >= 15000) then
        tambahItem(daftar, lihat, tostring(p), ukuran)
      end
    end)
    if not ok2 then catatGalat(g, "MediaStore baris gagal: " .. tostring(e2)) end
  end
  pcall(function() c.close() end)
end

local function pindaiSatu(jalur, dalam, daftar, lihat, g, tumpukan)
  local ok, err = pcall(function()
    local folder = File(jalur)
    if not folder.exists() then return end
    local arr = folder.listFiles()
    if arr == nil then
      if dalam == 0 then
        catatGalat(g, "Folder " .. jalur .. " tidak bisa dibaca, kemungkinan izin penyimpanan belum diberikan")
      end
      return
    end
    for i = 0, panjangLarik(arr) - 1 do
      local f = arr[i]
      local nama = tostring(f.getName())
      if f.isDirectory() then
        if dalam < 5 and nama ~= "Android" and string.sub(nama, 1, 1) ~= "." then
          tumpukan[#tumpukan + 1] = { jalur = tostring(f.getAbsolutePath()), dalam = dalam + 1 }
        end
      else
        local ekst = string.lower(string.match(nama, "%.(%w+)$") or "")
        if EKSTENSI[ekst] then
          tambahItem(daftar, lihat, tostring(f.getAbsolutePath()), f.length())
        end
      end
    end
  end)
  if not ok then catatGalat(g, "Folder " .. jalur .. " gagal dibaca: " .. tostring(err)) end
end

local function akarPenyimpanan()
  local akar = {}
  local lihat = {}
  pcall(function()
    local dirs = ctx.getExternalFilesDirs(nil)
    for i = 0, panjangLarik(dirs) - 1 do
      local d = dirs[i]
      if d ~= nil then
        local r = string.match(tostring(d.getAbsolutePath()), "^(.-)/Android/")
        if r and not lihat[r] then
          lihat[r] = true
          akar[#akar + 1] = r
        end
      end
    end
  end)
  if not lihat["/storage/emulated/0"] then akar[#akar + 1] = "/storage/emulated/0" end
  return akar
end

local function muatDaftarLagu(paksa, selesai)
  if DJL.daftar and not paksa then
    selesai(DJL.daftar)
    return
  end
  toast("Memindai lagu")
  local daftar, lihat = {}, {}
  local g = { n = 0 }
  local tumpukan = {}
  local dikunjungi = {}
  local tahap = 0
  DJL.giliranPindai = (DJL.giliranPindai or 0) + 1
  local giliran = DJL.giliranPindai

  local function akhiri()
    table.sort(daftar, function(a, b) return a.nl < b.nl end)
    DJL.daftar = daftar
    if #daftar == 0 and g.n > 0 then
      tampilGalat("Pemindaian lagu gagal", tostring(g.n) .. " galat, yang pertama:\n" .. tostring(g.pertama), function() selesai(daftar) end)
      return
    end
    if g.n > 0 then
      toast(#daftar .. " lagu ditemukan, " .. g.n .. " folder atau berkas dilewati karena galat")
    end
    selesai(daftar)
  end

  local function langkah()
    if DJL.giliranPindai ~= giliran then return end
    local batas = System.nanoTime() + 20000000
    if tahap == 0 then
      tahap = 1
      pindaiMediaStore(daftar, lihat, g)
      local sumber = {}
      for folder in string.gmatch(pengaturan.folder, "[^;]+") do
        local bersih = pangkas(folder)
        if bersih ~= "" then sumber[#sumber + 1] = bersih end
      end
      for _, akar in ipairs(akarPenyimpanan()) do sumber[#sumber + 1] = akar end
      for k = #sumber, 1, -1 do
        tumpukan[#tumpukan + 1] = { jalur = sumber[k], dalam = 0 }
      end
    end
    while #tumpukan > 0 and #daftar <= 6000 and g.n <= 50 and System.nanoTime() < batas do
      local e = table.remove(tumpukan)
      if not dikunjungi[e.jalur] then
        dikunjungi[e.jalur] = true
        pindaiSatu(e.jalur, e.dalam, daftar, lihat, g, tumpukan)
      end
    end
    if #tumpukan > 0 and #daftar <= 6000 and g.n <= 50 then
      kirimUI(aman(langkah), 12)
    else
      akhiri()
    end
  end

  kirimUI(aman(langkah), 50)
end

local function durasiLagu(path)
  local d = 180
  pcall(function()
    local ext = buatJava("android.media.MediaExtractor")
    ext.setDataSource(path)
    for i = 0, ext.getTrackCount() - 1 do
      local f = ext.getTrackFormat(i)
      local mime = tostring(f.getString("mime"))
      if string.sub(mime, 1, 6) == "audio/" then
        d = f.getLong("durationUs") / 1000000
        break
      end
    end
    ext.release()
  end)
  return d
end

local function dekodeJendela(path, awalDetik, panjangDetik)
  bersihkanSD()
  local ext = buatJava("android.media.MediaExtractor")
  DJL.sd = { ext = ext }
  ext.setDataSource(path)
  local jalur = -1
  local format = nil
  for i = 0, ext.getTrackCount() - 1 do
    local f = ext.getTrackFormat(i)
    local mime = tostring(f.getString("mime"))
    if string.sub(mime, 1, 6) == "audio/" then
      jalur = i
      format = f
      break
    end
  end
  if jalur < 0 then
    error("Tidak ada jalur audio di berkas ini")
  end
  ext.selectTrack(jalur)
  local mime = tostring(format.getString("mime"))
  local sr = 44100
  local kanal = 2
  pcall(function() sr = format.getInteger("sample-rate") end)
  pcall(function() kanal = format.getInteger("channel-count") end)
  local d = math.max(1, math.floor(sr / 7500 + 0.5))
  local m = math.min(d, 4)
  local target = math.floor(panjangDetik * sr / d)
  local codec = luajava.bindClass("android.media.MediaCodec").createDecoderByType(mime)
  DJL.sd.codec = codec
  codec.configure(format, nil, nil, 0)
  codec.start()
  ext.seekTo(math.floor(awalDetik * 1000000), 0)
  local info = buatJava("android.media.MediaCodec$BufferInfo")
  local hasil = {}
  local nh = 0
  local awalNyata = nil
  local selesaiMasuk = false
  local selesaiKeluar = false
  local globalFrame = 0
  local prox = 0
  local kapasitas = 8192
  local pendek = larik("Short", kapasitas)
  local BO = luajava.bindClass("java.nio.ByteOrder")
  local putaran = 0
  local mulaiJam = os.time()
  while not selesaiKeluar and nh < target do
    putaran = putaran + 1
    if DJL.batal or putaran > 60000 or os.time() - mulaiJam > 300 then break end
    if not selesaiMasuk then
      local ix = codec.dequeueInputBuffer(10000)
      if ix >= 0 then
        local buf = codec.getInputBuffer(ix)
        local n = ext.readSampleData(buf, 0)
        if n < 0 then
          codec.queueInputBuffer(ix, 0, 0, 0, 4)
          selesaiMasuk = true
        else
          codec.queueInputBuffer(ix, 0, n, ext.getSampleTime(), 0)
          ext.advance()
        end
      end
    end
    local ox = codec.dequeueOutputBuffer(info, 10000)
    if ox >= 0 then
      local ob = codec.getOutputBuffer(ox)
      local ukuran = info.size
      if ukuran > 0 then
        if awalNyata == nil then awalNyata = info.presentationTimeUs / 1000000 end
        ob.position(info.offset)
        ob.limit(info.offset + ukuran)
        local sb = ob.order(BO.LITTLE_ENDIAN).asShortBuffer()
        local jumlah = math.floor(ukuran / 2)
        if jumlah > kapasitas then
          kapasitas = jumlah
          pendek = larik("Short", kapasitas)
        end
        sb.get(pendek, 0, jumlah)
        local frames = math.floor(jumlah / kanal)
        while prox < globalFrame + frames and nh < target do
          local lf = prox - globalFrame
          local s, c = 0, 0
          for q = 0, m - 1 do
            if lf + q < frames then
              s = s + pendek[(lf + q) * kanal]
              c = c + 1
            end
          end
          nh = nh + 1
          hasil[nh] = s / c / 32768
          prox = prox + d
        end
        globalFrame = globalFrame + frames
      end
      codec.releaseOutputBuffer(ox, false)
      if math.floor(info.flags / 4) % 2 == 1 then selesaiKeluar = true end
      napas()
    elseif ox == -2 then
      local of = codec.getOutputFormat()
      pcall(function() sr = of.getInteger("sample-rate") end)
      pcall(function() kanal = of.getInteger("channel-count") end)
    end
  end
  bersihkanSD()
  return hasil, sr / d, awalNyata or awalDetik
end

function D.siapkanFFT(n)
  local bits = 0
  local tmp = n
  while tmp > 1 do
    tmp = math.floor(tmp / 2)
    bits = bits + 1
  end
  local rev = {}
  for i = 0, n - 1 do
    local r = 0
    local v = i
    for b = 1, bits do
      r = r * 2 + (v % 2)
      v = math.floor(v / 2)
    end
    rev[i + 1] = r + 1
  end
  local cs, sn = {}, {}
  for i = 0, n / 2 - 1 do
    local a = -2 * math.pi * i / n
    cs[i + 1] = math.cos(a)
    sn[i + 1] = math.sin(a)
  end
  local hann = {}
  for i = 0, n - 1 do
    hann[i + 1] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))
  end
  return { n = n, rev = rev, cs = cs, sn = sn, hann = hann }
end

function D.jalankanFFT(F, re, im)
  local n = F.n
  local rev = F.rev
  local cs, sn = F.cs, F.sn
  for i = 1, n do
    local j = rev[i]
    if j > i then
      re[i], re[j] = re[j], re[i]
      im[i], im[j] = im[j], im[i]
    end
  end
  local ukuran = 2
  while ukuran <= n do
    local setengah = math.floor(ukuran / 2)
    local langkah = math.floor(n / ukuran)
    for mulai = 1, n, ukuran do
      local k = 1
      for j = mulai, mulai + setengah - 1 do
        local wr = cs[k]
        local wi = sn[k]
        local l = j + setengah
        local tr = re[l] * wr - im[l] * wi
        local ti = re[l] * wi + im[l] * wr
        re[l] = re[j] - tr
        im[l] = im[j] - ti
        re[j] = re[j] + tr
        im[j] = im[j] + ti
        k = k + langkah
      end
    end
    ukuran = ukuran * 2
  end
end

local POLA_CHORD = {
  { suf = "", kualitas = "Mayor", interval = { 0, 4, 7 } },
  { suf = "m", kualitas = "Minor", interval = { 0, 3, 7 } },
  { suf = "dim", kualitas = "Diminished", interval = { 0, 3, 6 } },
  { suf = "aug", kualitas = "Augmented", interval = { 0, 4, 8 } },
  { suf = "sus2", kualitas = "Suspended 2", interval = { 0, 2, 7 } },
  { suf = "sus4", kualitas = "Suspended 4", interval = { 0, 5, 7 } },
  { suf = "7", kualitas = "Dominant seventh", interval = { 0, 4, 7, 10 } },
  { suf = "maj7", kualitas = "Major seventh", interval = { 0, 4, 7, 11 } },
  { suf = "m7", kualitas = "Minor seventh", interval = { 0, 3, 7, 10 } },
  { suf = "m7b5", kualitas = "Half-diminished seventh", interval = { 0, 3, 6, 10 } },
  { suf = "dim7", kualitas = "Diminished seventh", interval = { 0, 3, 6, 9 } },
  { suf = "6", kualitas = "Major sixth", interval = { 0, 4, 7, 9 } },
  { suf = "m6", kualitas = "Minor sixth", interval = { 0, 3, 7, 9 } },
  { suf = "add9", kualitas = "Major add nine", interval = { 0, 2, 4, 7 } },
  { suf = "9", kualitas = "Dominant ninth", interval = { 0, 2, 4, 7, 10 } },
  { suf = "maj9", kualitas = "Major ninth", interval = { 0, 2, 4, 7, 11 } },
  { suf = "m9", kualitas = "Minor ninth", interval = { 0, 2, 3, 7, 10 } }
}

function D.nilaiChord(kroma, bass)
  local total, norm2 = 0, 0
  local nilai = {}
  for i = 1, 12 do
    local v = math.max(0, tonumber(kroma[i]) or 0)
    nilai[i] = v
    total = total + v
    norm2 = norm2 + v * v
  end
  if total < 1e-8 or norm2 < 1e-12 then return nil, 0 end

  local bassPc, bassRasio = nil, 0
  if bass then
    local midiTerendah = tonumber(bass[13])
    if midiTerendah then
      bassPc = midiTerendah % 12
      bassRasio = tonumber(bass[14]) or 1.25
    else
      local pertama, kedua = -1, -1
      for i = 1, 12 do
        local v = tonumber(bass[i]) or 0
        if v > pertama then
          kedua, pertama, bassPc = pertama, v, i - 1
        elseif v > kedua then
          kedua = v
        end
      end
      if pertama > 0 then bassRasio = pertama / math.max(0.000001, kedua) end
    end
  end

  local terbaik, skorTerbaik, skorKedua = nil, -1, -1
  local panjang = math.sqrt(norm2)
  for akar = 0, 11 do
    for _, pola in ipairs(POLA_CHORD) do
      local ada, bobot = {}, {}
      local bobotTotal, nadaDalam, nadaLuar2 = 0, 0, 0
      for _, intervalo in ipairs(pola.interval) do
        local pc = (akar + intervalo) % 12
        local w = intervalo == 0 and 1.30
          or ((intervalo == 3 or intervalo == 4) and 1.12
          or ((intervalo == 6 or intervalo == 7 or intervalo == 8
            or (pola.suf == "sus2" and intervalo == 2)
            or (pola.suf == "sus4" and intervalo == 5)) and 0.92 or 0.72))
        ada[pc + 1] = true
        bobot[pc + 1] = w
        bobotTotal = bobotTotal + w * w
      end
      local dot = 0
      local inti, tambahan = {}, {}
      for _, intervalo in ipairs(pola.interval) do
        if intervalo == 0 or intervalo == 3 or intervalo == 4
          or intervalo == 6 or intervalo == 7 or intervalo == 8
          or (pola.suf == "sus2" and intervalo == 2)
          or (pola.suf == "sus4" and intervalo == 5) then
          inti[#inti + 1] = intervalo
        else
          tambahan[#tambahan + 1] = intervalo
        end
      end
      for i = 1, 12 do
        local v = nilai[i]
        if ada[i] then
          dot = dot + v * bobot[i]
          nadaDalam = nadaDalam + v
        else
          nadaLuar2 = nadaLuar2 + v * v
        end
      end
      local cosine = dot / (panjang * math.sqrt(bobotTotal) + 1e-9)
      local proporsi = nadaDalam / (total + 1e-9)
      local luar = math.sqrt(nadaLuar2) / (panjang + 1e-9)
      local skor = 0.62 * cosine + 0.38 * proporsi - 0.18 * luar
      if #tambahan > 0 and #inti > 0 then
        local energiInti, energiTambahan = 0, 0
        for _, intervalo in ipairs(inti) do
          energiInti = energiInti + nilai[((akar + intervalo) % 12) + 1]
        end
        for _, intervalo in ipairs(tambahan) do
          energiTambahan = energiTambahan + nilai[((akar + intervalo) % 12) + 1]
        end
        local rataInti = energiInti / #inti
        local rataTambahan = energiTambahan / #tambahan
        local rasioTambahan = rataTambahan / (rataInti + 1e-9)
        skor = skor - math.max(0, 0.65 - rasioTambahan) * 0.70 * #tambahan
      end
      skor = skor - math.max(0, #pola.interval - 3) * 0.008
      if bassPc ~= nil and bassRasio >= 1.10 then
        if bassPc == akar then
          skor = skor + 0.075
        elseif ada[bassPc + 1] then
          skor = skor + 0.020
        else
          skor = skor - 0.050
        end
      end
      if skor > skorTerbaik then
        skorKedua = skorTerbaik
        skorTerbaik = skor
        terbaik = { akar = akar, pola = pola, bassPc = bassPc, bassRasio = bassRasio }
      elseif skor > skorKedua then
        skorKedua = skor
      end
    end
  end

  if not terbaik then return nil, 0 end
  if skorTerbaik > 1 then skorTerbaik = 1 end
  local notas, anggota = {}, {}
  for _, intervalo in ipairs(terbaik.pola.interval) do
    local pc = (terbaik.akar + intervalo) % 12
    notas[#notas + 1] = NAMA_NADA[pc + 1]
    anggota[pc + 1] = true
  end

  local bassNama = ""
  if terbaik.bassPc ~= nil and terbaik.bassRasio >= 1.22
    and anggota[terbaik.bassPc + 1] and terbaik.bassPc ~= terbaik.akar then
    bassNama = NAMA_NADA[terbaik.bassPc + 1]
  end
  local nama = NAMA_NADA[terbaik.akar + 1] .. terbaik.pola.suf
  if bassNama ~= "" then nama = nama .. "/" .. bassNama end

  local selisih = skorTerbaik - math.max(0, skorKedua)
  local keyakinan = math.max(0, math.min(1, selisih * 4 + (skorTerbaik - 0.38) * 1.2))
  return {
    nama = nama,
    akar = NAMA_NADA[terbaik.akar + 1],
    kualitas = terbaik.pola.kualitas,
    nada = table.concat(notas, ", "),
    bass = bassNama ~= "" and bassNama
      or (terbaik.bassPc ~= nil and NAMA_NADA[terbaik.bassPc + 1] or "Tidak terdeteksi"),
    keyakinan = keyakinan
  }, skorTerbaik
end

function D.tambahChroma(x, fs, kroma, daftarChord, offsetDetik)
  local N = 4096
  local HOP = math.floor(N / 2)
  if not DJL.fft then DJL.fft = D.siapkanFFT(N) end
  local F = DJL.fft
  local peta = {}
  for k = 1, N / 2 - 1 do
    local f = k * fs / N
    if f >= 110 and f <= 1600 then
      local midi = math.floor(12 * math.log(f / 440) / math.log(2) + 69 + 0.5)
      peta[k + 1] = midi % 12
    end
  end

  local nadaAnalisis = {}
  for midi = 33, 84 do
    local frekuensi = 440 * math.pow(2, (midi - 69) / 12)
    local harmonik = {}
    for h = 1, 6 do
      local fh = frekuensi * h
      if fh < fs * 0.47 then
        local bin = math.floor(fh * N / fs + 0.5) + 1
        if bin >= 2 and bin <= N / 2 then
          harmonik[#harmonik + 1] = { bin = bin, bobot = 1 / math.pow(h, 0.88) }
        end
      end
    end
    nadaAnalisis[#nadaAnalisis + 1] = {
      midi = midi,
      pc = midi % 12,
      bobotNada = 1 / (1 + math.max(0, midi - 60) * 0.012),
      harmonik = harmonik
    }
  end

  local nadaBass = {}
  for midi = 28, 52 do
    local f0 = 440 * math.pow(2, (midi - 69) / 12)
    local bin = math.floor(f0 * N / fs + 0.5) + 1
    if bin >= 2 and bin <= N / 2 then
      local bin2 = math.floor(2 * f0 * N / fs + 0.5) + 1
      nadaBass[#nadaBass + 1] = { midi = midi, pc = midi % 12, bin = bin, bin2 = bin2 }
    end
  end

  local re, im = {}, {}
  local s = 1
  local nomorFrame = 0
  local awalKelompok = 0
  local jumlahFrame = 0
  local kelompokChroma = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  local kelompokBass = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  local kelompokBassMidi = {}
  for i = 1, 25 do kelompokBassMidi[i] = 0 end
  local ukuranKelompok = math.max(2, math.floor(fs * 0.90 / HOP + 0.5))

  local function magnitudo(k)
    if k < 2 or k > N / 2 then return 0 end
    local a = math.sqrt(re[k] * re[k] + im[k] * im[k])
    local b = math.sqrt(re[k - 1] * re[k - 1] + im[k - 1] * im[k - 1])
    local c = 0
    if k < N / 2 then c = math.sqrt(re[k + 1] * re[k + 1] + im[k + 1] * im[k + 1]) end
    if b > a then a = b end
    if c > a then a = c end
    return a
  end

  local function simpanKelompok()
    if daftarChord and jumlahFrame > 0 then
      local bassInfo = {}
      local bassMaks = 0
      for i = 1, 12 do bassInfo[i] = kelompokBass[i] end
      for i = 1, 25 do
        if kelompokBassMidi[i] > bassMaks then bassMaks = kelompokBassMidi[i] end
      end
      if bassMaks > 0.080 then
        for i = 1, 25 do
          if kelompokBassMidi[i] >= bassMaks * 0.24 then
            bassInfo[13] = i + 27
            bassInfo[14] = 1.25
            break
          end
        end
      end
      local hasil, skor = D.nilaiChord(kelompokChroma, bassInfo)
      if hasil and skor >= 0.43 then
        local mulai = (offsetDetik or 0) + awalKelompok * HOP / fs
        local akhir = (offsetDetik or 0) + nomorFrame * HOP / fs
        daftarChord[#daftarChord + 1] = {
          nama = hasil.nama,
          akar = hasil.akar,
          kualitas = hasil.kualitas,
          nada = hasil.nada,
          bass = hasil.bass,
          keyakinan = hasil.keyakinan,
          mulai = mulai,
          akhir = akhir,
          skor = skor
        }
      end
    end
    kelompokChroma = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    kelompokBass = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    kelompokBassMidi = {}
    for i = 1, 25 do kelompokBassMidi[i] = 0 end
    jumlahFrame = 0
  end

  while s + N - 1 <= #x do
    if DJL.batal then return end
    for i = 1, N do
      re[i] = x[s + i - 1] * F.hann[i]
      im[i] = 0
    end
    D.jalankanFFT(F, re, im)

    if nomorFrame % 2 == 0 then
      local akumKunci = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
      local totalKunci = 0
      for k = 2, N / 2 do
        local pc = peta[k]
        if pc ~= nil then
          local mag = math.sqrt(re[k] * re[k] + im[k] * im[k])
          akumKunci[pc + 1] = akumKunci[pc + 1] + mag
          totalKunci = totalKunci + mag
        end
      end
      if totalKunci > 1e-6 then
        for i = 1, 12 do
          kroma[i] = kroma[i] + akumKunci[i] / totalKunci
        end
      end
    end

    local akumNada = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    local akumBass = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    local akumBassMidi = {}
    for i = 1, 25 do akumBassMidi[i] = 0 end
    local totalNada, totalBass = 0, 0

    for _, n in ipairs(nadaAnalisis) do
      local nilai = 0
      for _, h in ipairs(n.harmonik) do
        nilai = nilai + magnitudo(h.bin) * h.bobot
      end
      nilai = nilai * n.bobotNada
      akumNada[n.pc + 1] = akumNada[n.pc + 1] + nilai
      totalNada = totalNada + nilai
    end

    for _, n in ipairs(nadaBass) do
      local v = magnitudo(n.bin)
      if n.bin2 <= N / 2 then v = v + magnitudo(n.bin2) * 0.28 end
      akumBass[n.pc + 1] = akumBass[n.pc + 1] + v
      akumBassMidi[n.midi - 27] = akumBassMidi[n.midi - 27] + v
      totalBass = totalBass + v
    end

    if totalNada > 1e-7 then
      for i = 1, 12 do
        kelompokChroma[i] = kelompokChroma[i] + akumNada[i] / totalNada
      end
      if totalBass > 1e-7 then
        for i = 1, 12 do
          kelompokBass[i] = kelompokBass[i] + akumBass[i] / totalBass
        end
        for i = 1, 25 do
          kelompokBassMidi[i] = kelompokBassMidi[i] + akumBassMidi[i] / totalBass
        end
      end
      jumlahFrame = jumlahFrame + 1
    end

    nomorFrame = nomorFrame + 1
    if nomorFrame - awalKelompok >= ukuranKelompok then
      simpanKelompok()
      awalKelompok = nomorFrame
    end
    s = s + HOP
    napas()
  end
  simpanKelompok()
end

function D.korelasi(a, b)
  local ma, mb = 0, 0
  for i = 1, 12 do
    ma = ma + a[i]
    mb = mb + b[i]
  end
  ma = ma / 12
  mb = mb / 12
  local sab, saa, sbb = 0, 0, 0
  for i = 1, 12 do
    local da = a[i] - ma
    local db = b[i] - mb
    sab = sab + da * db
    saa = saa + da * da
    sbb = sbb + db * db
  end
  if saa <= 0 or sbb <= 0 then return 0 end
  return sab / math.sqrt(saa * sbb)
end

function D.tentukanKunci(kroma)
  local daftar = {}
  for t = 0, 11 do
    local rot = {}
    for i = 0, 11 do rot[i + 1] = kroma[((t + i) % 12) + 1] end
    daftar[#daftar + 1] = { pc = t, mode = 1, skor = D.korelasi(rot, PROFIL_MAYOR) }
    daftar[#daftar + 1] = { pc = t, mode = 0, skor = D.korelasi(rot, PROFIL_MINOR) }
  end
  table.sort(daftar, function(a, b) return a.skor > b.skor end)
  return daftar[1], daftar[2]
end

function D.hitungOnset(x, fs)
  local N = 512
  if not DJL.fft512 then DJL.fft512 = D.siapkanFFT(N) end
  local F = DJL.fft512
  local hop = math.max(32, math.floor(fs * 0.0107 + 0.5))
  local jml = math.floor((#x - N) / hop) + 1
  if jml < 300 then return nil end
  local jk, cacah = 0, 0
  for i = 1, #x, 3 do
    jk = jk + x[i] * x[i]
    cacah = cacah + 1
  end
  local rms = math.sqrt(jk / cacah)
  if rms < 1e-5 then return nil end
  local skala = 0.1 / rms
  local NB = 24
  local fmin = 40
  local fmaks = math.min(3400, 0.47 * fs)
  local lr = math.log((fmaks / fmin) ^ (1 / NB))
  local band = {}
  for k = 1, N / 2 - 1 do
    local f = k * fs / N
    if f >= fmin and f < fmaks then
      local b = math.floor(math.log(f / fmin) / lr) + 1
      if b > NB then b = NB end
      band[k + 1] = b
    end
  end
  local win = {}
  for i = 1, N do win[i] = F.hann[i] * skala end
  local re, im = {}, {}
  local EA, EB = {}, {}
  local Lp, Ln = {}, {}
  for b = 0, NB + 1 do
    Lp[b] = 0
    Ln[b] = 0
  end
  local fluks = {}
  local function fluksDari(E)
    for b = 1, NB do Ln[b] = math.log(1 + E[b]) end
    local s = 0
    for b = 1, NB do
      local ref = Lp[b]
      local a = Lp[b - 1]
      if a > ref then ref = a end
      a = Lp[b + 1]
      if a > ref then ref = a end
      local d = Ln[b] - ref
      if d > 0 then s = s + d end
    end
    for b = 1, NB do Lp[b] = Ln[b] end
    return s
  end
  local t = 1
  while t <= jml do
    if DJL.batal then return nil end
    local s1 = (t - 1) * hop
    local s2 = t * hop
    local ada2 = (t + 1 <= jml)
    for i = 1, N do
      re[i] = x[s1 + i] * win[i]
      if ada2 then im[i] = x[s2 + i] * win[i] else im[i] = 0 end
    end
    D.jalankanFFT(F, re, im)
    for b = 1, NB do
      EA[b] = 0
      EB[b] = 0
    end
    for k = 1, N / 2 - 1 do
      local b = band[k + 1]
      if b then
        local p, q = k + 1, N - k + 1
        local zr, zi, yr, yi = re[p], im[p], re[q], im[q]
        local ar, ai = zr + yr, zi - yi
        local br, bi = zi + yi, yr - zr
        EA[b] = EA[b] + 0.5 * math.sqrt(ar * ar + ai * ai)
        EB[b] = EB[b] + 0.5 * math.sqrt(br * br + bi * bi)
      end
    end
    fluks[t] = fluksDari(EA)
    if ada2 then fluks[t + 1] = fluksDari(EB) end
    t = t + 2
    napas()
  end
  return { f = fluks, hopSec = hop / fs, n = jml, ofsSec = 0.68 * N / fs }
end

function D.olahOnset(w)
  local f, n = w.f, w.n
  local M = math.floor(0.3 / w.hopSec + 0.5)
  local ps = { [0] = 0 }
  for t = 1, n do ps[t] = ps[t - 1] + f[t] end
  local o = {}
  local tot = 0
  for t = 1, n do
    local a = t - M
    if a < 1 then a = 1 end
    local b = t + M
    if b > n then b = n end
    local v = f[t] - (ps[b] - ps[a - 1]) / (b - a + 1)
    if v < 0 then v = 0 end
    o[t] = v
    tot = tot + v
  end
  local rata = tot / n
  local oc = {}
  for t = 1, n do oc[t] = o[t] - rata end
  local hal = {}
  for t = 1, n do
    local a = o[t - 1] or o[t]
    local c = o[t + 1] or o[t]
    hal[t] = 0.25 * a + 0.5 * o[t] + 0.25 * c
  end
  w.oc = oc
  w.hal = hal
  w.rata = rata
  w.f = nil
end

function D.hitungR(w, lmin, lmaks)
  local oc = w.oc
  local n = w.n
  local R = {}
  local e0 = 0
  for t = 1, n do e0 = e0 + oc[t] * oc[t] end
  e0 = e0 / n
  if e0 <= 0 then e0 = 1 end
  for lag = lmin, lmaks do
    if lag >= n - 10 then
      R[lag] = 0
    else
      local jumlah = 0
      for t = 1, n - lag do
        jumlah = jumlah + oc[t] * oc[t + lag]
      end
      R[lag] = jumlah / (n - lag) / e0
    end
    if lag % 8 == 0 then napas() end
  end
  return R
end

function D.skorSisir(hal, n, P)
  local pf = math.floor(P)
  local terbaik, fase = -1e30, 0
  for f0 = 0, pf do
    local jumlah, k = 0, 0
    local pos = f0
    while pos <= n - 2 do
      local i0 = math.floor(pos)
      local fr = pos - i0
      jumlah = jumlah + hal[i0 + 1] * (1 - fr) + hal[i0 + 2] * fr
      k = k + 1
      pos = f0 + k * P
    end
    if k > 0 then jumlah = jumlah / k end
    if jumlah > terbaik then
      terbaik = jumlah
      fase = f0
    end
  end
  return terbaik, fase
end

function D.bobotPrior(bpm)
  local oktaf = math.log(bpm / 120) / math.log(2)
  return math.exp(-0.5 * (oktaf / 0.7) ^ 2)
end

function D.pilihTempo(Rg, hopSec, lmin, lmax)
  local S = {}
  for l = lmin, lmax do
    local d2, d3 = Rg[2 * l] or 0, Rg[3 * l] or 0
    if d3 > d2 then d2 = d3 end
    S[l] = Rg[l] + 0.4 * d2 + 0.2 * (Rg[4 * l] or 0)
  end
  local jumlahS, banyakS = 0, 0
  for l = lmin, lmax do
    if S[l] > 0 then
      jumlahS = jumlahS + S[l]
      banyakS = banyakS + 1
    end
  end
  local kandidat = {}
  for l = lmin + 1, lmax - 1 do
    if S[l] > 0 and S[l] > S[l - 1] and S[l] >= S[l + 1] then
      local bpm = 60 / (l * hopSec)
      kandidat[#kandidat + 1] = { l = l, skor = S[l] * D.bobotPrior(bpm), s = S[l] }
    end
  end
  table.sort(kandidat, function(a, b) return a.skor > b.skor end)
  local rata = 1
  if banyakS > 0 then rata = jumlahS / banyakS end
  return kandidat
end

function D.sempurnakanTempo(semuaW, l0, rentang, langkah)
  rentang = rentang or 0.03
  langkah = langkah or 0.0003
  local batas = math.floor(rentang / langkah + 0.5)
  local terbaikSkor, terbaikP = -1e30, l0
  local kurva = {}
  for i = -batas, batas do
    local P = l0 * (1 + i * langkah)
    local jumlah = 0
    for _, w in ipairs(semuaW) do
      local sk = D.skorSisir(w.hal, w.n, P)
      jumlah = jumlah + sk / (w.rata + 1e-9)
    end
    kurva[i] = jumlah
    if jumlah > terbaikSkor then
      terbaikSkor = jumlah
      terbaikP = P
    end
    napas()
  end
  local ib = math.floor((terbaikP / l0 - 1) / langkah + 0.5)
  local a, b, c = kurva[ib - 1], kurva[ib], kurva[ib + 1]
  local delta = 0
  if a and c then
    local den = a - 2 * b + c
    if den ~= 0 then delta = 0.5 * (a - c) / den end
    if delta > 1 then delta = 1 elseif delta < -1 then delta = -1 end
  end
  return l0 * (1 + (ib + delta) * langkah), terbaikSkor
end

function D.analisisInti(semuaW, kroma)
  local hopSec = semuaW[1].hopSec
  local lmin = math.ceil(60 / (220 * hopSec))
  local lmax = math.floor(60 / (45 * hopSec))
  local Rg = {}
  for _, w in ipairs(semuaW) do
    local R = D.hitungR(w, lmin, lmax * 4)
    for lag, v in pairs(R) do Rg[lag] = (Rg[lag] or 0) + v / #semuaW end
  end
  local kandidat = D.pilihTempo(Rg, hopSec, lmin, lmax)
  if #kandidat == 0 then return nil, "Denyut lagu tidak terdeteksi jelas" end
  local calon, terlihat = {}, {}
  local jumlahKandidat = math.min(10, #kandidat)
  for i = 1, jumlahKandidat do
    local dasar = kandidat[i]
    for _, faktor in ipairs({ 0.5, 1, 2 }) do
      local l0 = dasar.l * faktor
      local bpm0 = 60 / (l0 * hopSec)
      if bpm0 >= 45 and bpm0 <= 220 then
        local kunci = math.floor(l0 * 100 + 0.5)
        if not terlihat[kunci] then
          terlihat[kunci] = true
          local P, skor = D.sempurnakanTempo(semuaW, l0, 0.015, 0.0003)
          local bpm = 60 / (P * hopSec)
          if bpm >= 45 and bpm <= 220 then
            local lag = math.max(lmin, math.min(lmax, math.floor(P + 0.5)))
            local auto = (Rg[lag] or 0) + 0.4 * (Rg[lag * 2] or 0) + 0.2 * (Rg[lag * 3] or 0)
            calon[#calon + 1] = { P = P, bpm = bpm, skor = skor, auto = auto, prior = D.bobotPrior(bpm) }
          end
        end
      end
    end
  end
  if #calon == 0 then return nil, "Kandidat tempo tidak berada dalam rentang yang didukung" end
  local skorMaks, autoMaks = 1e-9, 1e-9
  for _, c in ipairs(calon) do
    if c.skor > skorMaks then skorMaks = c.skor end
    if c.auto > autoMaks then autoMaks = c.auto end
  end
  local terpilih, nilaiTerpilih = calon[1], -1e30
  for _, c in ipairs(calon) do
    c.nilai = 0.58 * (c.skor / skorMaks) + 0.22 * (c.auto / autoMaks) + 0.20 * c.prior
    if c.nilai > nilaiTerpilih then
      nilaiTerpilih = c.nilai
      terpilih = c
    end
  end
  if terpilih.bpm < 70 then
    local cepat, nilaiCepat = nil, -1e30
    for _, c in ipairs(calon) do
      local rasio = c.bpm / terpilih.bpm
      local dukunganSkor = c.skor / math.max(terpilih.skor, 1e-9)
      local dukunganAuto = c.auto / math.max(terpilih.auto, 1e-9)
      if rasio >= 1.94 and rasio <= 2.06
        and dukunganSkor >= 0.55
        and dukunganAuto >= 0.45
        and c.auto >= autoMaks * 0.12
        and c.prior > terpilih.prior then
        local nilai = 0.45 * (c.skor / skorMaks)
          + 0.35 * (c.auto / autoMaks)
          + 0.20 * c.prior
        if nilai > nilaiCepat then
          cepat = c
          nilaiCepat = nilai
        end
      end
    end
    if cepat then terpilih = cepat end
  end
  local P, skorSisirTotal = terpilih.P, terpilih.skor
  local bpm = 60 / (P * hopSec)
  local tengah = math.ceil(#semuaW / 2)
  local wt = semuaW[tengah]
  local _, fase = D.skorSisir(wt.hal, wt.n, P)
  local awalTengah = wt.awal
  local k1, k2 = D.tentukanKunci(kroma)
  return {
    v = 4,
    bpm = bpm,
    rasio = skorSisirTotal / #semuaW,
    pc1 = k1.pc, mode1 = k1.mode, skor1 = k1.skor,
    pc2 = k2.pc, mode2 = k2.mode, skor2 = k2.skor,
    awalMs = awalTengah * 1000,
    t0Ms = (awalTengah + fase * hopSec + wt.ofsSec) * 1000
  }
end

function D.kandidatTempoJendela(R, hopSec, lmin, lmax)
  local S = {}
  for l = lmin, lmax do
    local d2, d3 = R[2 * l] or 0, R[3 * l] or 0
    S[l] = R[l] + 0.35 * d2 + 0.15 * d3
  end
  local puncak = 1e-9
  local dasar = {}
  for l = lmin + 1, lmax - 1 do
    if S[l] > 0 and S[l] > S[l - 1] and S[l] >= S[l + 1] then
      local a, b, c = S[l - 1], S[l], S[l + 1]
      local den = a - 2 * b + c
      local d = 0
      if den ~= 0 then d = 0.5 * (a - c) / den end
      if d > 1 then d = 1 elseif d < -1 then d = -1 end
      dasar[#dasar + 1] = { lag = l + d, skor = b }
      if b > puncak then puncak = b end
    end
  end
  table.sort(dasar, function(x, y) return x.skor > y.skor end)
  local hasil, terlihat = {}, {}
  for i = 1, math.min(6, #dasar) do
    local b = dasar[i]
    for _, faktor in ipairs({ 0.5, 1, 2 }) do
      local lag = b.lag * faktor
      local bpm = 60 / (lag * hopSec)
      if bpm >= 45 and bpm <= 220 then
        local kunci = math.floor(lag * 100 + 0.5)
        if not terlihat[kunci] then
          terlihat[kunci] = true
          local li = math.max(lmin, math.min(lmax, math.floor(lag + 0.5)))
          local dukungan = (R[li] or 0) + 0.35 * (R[li * 2] or 0) + 0.15 * (R[li * 3] or 0)
          local skor = math.max(0, dukungan) * D.bobotPrior(bpm)
          hasil[#hasil + 1] = { bpm = bpm, skor = skor / puncak }
        end
      end
    end
  end
  table.sort(hasil, function(x, y) return x.skor > y.skor end)
  while #hasil > 12 do table.remove(hasil) end
  if #hasil == 0 then
    local bpm = 60 / (lmin * hopSec)
    hasil[1] = { bpm = bpm, skor = 0.001 }
  end
  return hasil
end

function D.pilihJalur(jendela)
  local n = #jendela
  local skorTotal, balik = {}, {}
  for t = 1, n do
    skorTotal[t], balik[t] = {}, {}
    for j, c in ipairs(jendela[t].kand) do
      local terbaik, dari = -1e30, 1
      if t == 1 then
        terbaik = 0
      else
        for i, p in ipairs(jendela[t - 1].kand) do
          local r = math.abs(math.log(c.bpm / p.bpm) / math.log(2))
          local biaya = 0
          if r > 0.06 then
            biaya = 0.35 + 5 * r
          elseif r > 0.015 then
            biaya = 0.15
          end
          local v = skorTotal[t - 1][i] - biaya
          if v > terbaik then
            terbaik = v
            dari = i
          end
        end
      end
      skorTotal[t][j] = terbaik + c.skor
      balik[t][j] = dari
    end
  end
  local jalur = {}
  local pilih, nilai = 1, -1e30
  for j, v in ipairs(skorTotal[n]) do
    if v > nilai then
      nilai = v
      pilih = j
    end
  end
  for t = n, 1, -1 do
    jalur[t] = jendela[t].kand[pilih].bpm
    pilih = balik[t][pilih]
  end
  return jalur
end

function D.potongBagian(bpm)
  local n = #bpm
  local x = {}
  local s1, s2 = { [0] = 0 }, { [0] = 0 }
  for i = 1, n do
    x[i] = math.log(bpm[i]) / math.log(2)
    s1[i] = s1[i - 1] + x[i]
    s2[i] = s2[i - 1] + x[i] * x[i]
  end
  local function biaya(i, j)
    local m = j - i + 1
    local sum = s1[j] - s1[i - 1]
    return (s2[j] - s2[i - 1]) - sum * sum / m
  end
  local LAMBDA = 0.004
  local F, P = { [0] = -LAMBDA }, {}
  for j = 1, n do
    local terbaik, bi = 1e30, 1
    for i = 1, j do
      local v = F[i - 1] + biaya(i, j) + LAMBDA
      if v < terbaik then
        terbaik = v
        bi = i
      end
    end
    F[j] = terbaik
    P[j] = bi
  end
  local hasil = {}
  local j = n
  while j >= 1 do
    local i = P[j]
    table.insert(hasil, 1, { i, j, 2 ^ ((s1[j] - s1[i - 1]) / (j - i + 1)) })
    j = i - 1
  end
  return hasil
end

function D.gabungTanjakan(seg)
  local hasil = {}
  local i = 1
  while i <= #seg do
    local j = i
    local arah = 0
    while j < #seg do
      local r = seg[j + 1].bpm / seg[j].bpm
      local d = 0
      if r > 1.015 and r < 1.12 then
        d = 1
      elseif r < 0.985 and r > 0.893 then
        d = -1
      end
      local pendek = (seg[j].akhir - seg[j].mulai) <= 14000 and (seg[j + 1].akhir - seg[j + 1].mulai) <= 14000
      if d == 0 or (arah ~= 0 and d ~= arah) or not pendek then break end
      arah = d
      j = j + 1
    end
    if j - i >= 2 then
      hasil[#hasil + 1] = { tipe = "bertahap", mulaiMs = seg[i].mulai, akhirMs = seg[j].akhir, bpm = seg[i].bpm, bpm2 = seg[j].bpm }
      i = j + 1
    else
      hasil[#hasil + 1] = { tipe = "tetap", mulaiMs = seg[i].mulai, akhirMs = seg[i].akhir, bpm = seg[i].bpm }
      i = i + 1
    end
  end
  return hasil
end

function D.buatPeta(chunks, dur, lapor)
  local hopSec = chunks[1].hopSec
  local ofsSec = chunks[1].ofsSec
  local N = math.floor(dur / hopSec) + 2
  local flux = {}
  for i = 1, N do flux[i] = 0 end
  for _, c in ipairs(chunks) do
    local idx0 = math.floor(c.awal / hopSec + 0.5)
    for i = 4, c.n do
      local k = idx0 + i
      if k >= 1 and k <= N then flux[k] = c.f[i] end
    end
  end
  local w = { f = flux, n = N, hopSec = hopSec }
  D.olahOnset(w)
  local Wf = math.floor(16 / hopSec + 0.5)
  local Sf = math.floor(5 / hopSec + 0.5)
  if N < Wf * 2 then return nil, "Lagu terlalu pendek untuk peta tempo" end
  local lmin = math.ceil(60 / (220 * hopSec))
  local lmax = math.floor(60 / (45 * hopSec))
  local jendela = {}
  local a = 1
  local totalJ = math.floor((N - Wf) / Sf) + 1
  local prev = 120
  while a + Wf - 1 <= N do
    if DJL.batal then return nil, "Dibatalkan" end
    local w2 = { n = Wf, hopSec = hopSec, rata = w.rata, oc = {}, hal = {} }
    for i = 1, Wf do
      w2.oc[i] = w.oc[a + i - 1]
      w2.hal[i] = w.hal[a + i - 1]
    end
    local R = D.hitungR(w2, lmin, lmax * 2)
    local kand = D.kandidatTempoJendela(R, hopSec, lmin, lmax)
    if #kand == 0 then kand = { { bpm = prev, skor = 0.01 } } end
    prev = kand[1].bpm
    jendela[#jendela + 1] = { a = a, kand = kand }
    lapor("Menyusun peta tempo " .. #jendela .. " dari " .. totalJ, 85 + 14 * #jendela / totalJ)
    napas()
    a = a + Sf
  end
  if #jendela < 2 then return nil, "Lagu terlalu pendek untuk peta tempo" end
  local jalur = D.pilihJalur(jendela)
  local pusat = {}
  for t, jd in ipairs(jendela) do pusat[t] = ((jd.a - 1) + Wf / 2) * hopSec * 1000 end
  local potong = D.potongBagian(jalur)
  local seg = {}
  for k, p in ipairs(potong) do
    local mulai = 0
    if k > 1 then mulai = (pusat[p[1] - 1] + pusat[p[1]]) / 2 end
    local akhir = dur * 1000
    if k < #potong then akhir = (pusat[p[2]] + pusat[p[2] + 1]) / 2 end
    seg[#seg + 1] = { mulai = mulai, akhir = akhir, bpm = p[3] }
  end
  local hasil = D.gabungTanjakan(seg)
  for _, b in ipairs(hasil) do
    local ia = math.max(1, math.floor(b.mulaiMs / 1000 / hopSec) + 1)
    local ib = math.min(N, math.floor(b.akhirMs / 1000 / hopSec) + 1)
    local pjgFr = ib - ia + 1
    b.t0Ms = b.mulaiMs
    if pjgFr * hopSec >= 8 then
      local ma, mb = ia, ib
      if b.tipe == "bertahap" then
        mb = math.min(ib, ia + math.floor(8 / hopSec))
      elseif pjgFr * hopSec > 40 then
        local tengah = math.floor((ia + ib) / 2)
        local setengah = math.floor(20 / hopSec)
        ma = tengah - setengah
        mb = tengah + setengah
      end
      local n2 = mb - ma + 1
      local w3 = { n = n2, hopSec = hopSec, rata = w.rata, oc = {}, hal = {} }
      for i = 1, n2 do
        w3.oc[i] = w.oc[ma + i - 1]
        w3.hal[i] = w.hal[ma + i - 1]
      end
      local l0 = 60 / (b.bpm * hopSec)
      local P = l0
      if b.tipe == "tetap" then
        local P2 = D.sempurnakanTempo({ w3 }, l0)
        if P2 then
          P = P2
          b.bpm = 60 / (P * hopSec)
        end
      end
      local _, ff = D.skorSisir(w3.hal, w3.n, P)
      b.t0Ms = ((ma - 1) + ff) * hopSec * 1000 + ofsSec * 1000
    end
    local akum = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    local bobot = 0
    if (b.akhirMs - b.mulaiMs) >= 16000 then
      for _, c in ipairs(chunks) do
        local ca = c.awal * 1000
        local cb = ca + c.n * hopSec * 1000
        local tumpang = math.min(cb, b.akhirMs) - math.max(ca, b.mulaiMs)
        if tumpang > 0 then
          local wgt = tumpang / (cb - ca)
          bobot = bobot + wgt
          for q = 1, 12 do akum[q] = akum[q] + c.kroma[q] * wgt end
        end
      end
    end
    if bobot > 0.5 then
      local k1 = D.tentukanKunci(akum)
      b.pc = k1.pc
      b.mode = k1.mode
      b.skor = k1.skor
    end
  end
  return hasil
end

function D.validasiPeta(peta, durasiDetik)
  if type(peta) ~= "table" or #peta == 0 then return nil end
  local batas = math.max(1000, (tonumber(durasiDetik) or 0) * 1000)
  local hasil = {}
  table.sort(peta, function(a, b) return (a.mulaiMs or 0) < (b.mulaiMs or 0) end)
  for _, b in ipairs(peta) do
    local mulai = math.max(0, tonumber(b.mulaiMs) or 0)
    local akhir = math.min(batas, tonumber(b.akhirMs) or batas)
    local bpm = tonumber(b.bpm) or 0
    local bpm2 = tonumber(b.bpm2) or bpm
    if akhir > mulai and bpm >= 40 and bpm <= 240 and bpm2 >= 40 and bpm2 <= 240 then
      local baru = { tipe = b.tipe == "bertahap" and "bertahap" or "tetap", mulaiMs = mulai, akhirMs = akhir, bpm = bpm, bpm2 = bpm2, t0Ms = math.max(mulai, math.min(akhir, tonumber(b.t0Ms) or mulai)), pc = b.pc, mode = b.mode, skor = b.skor }
      local lalu = hasil[#hasil]
      if lalu and baru.mulaiMs < lalu.akhirMs then baru.mulaiMs = lalu.akhirMs end
      if baru.akhirMs > baru.mulaiMs then
        if lalu and lalu.tipe == "tetap" and baru.tipe == "tetap" and math.abs(lalu.bpm - baru.bpm) <= 2.0 and baru.mulaiMs - lalu.akhirMs <= 1500 then
          lalu.akhirMs = baru.akhirMs
          lalu.bpm = (lalu.bpm + baru.bpm) / 2
          lalu.bpm2 = lalu.bpm
        else
          hasil[#hasil + 1] = baru
        end
      end
    end
  end
  if #hasil == 0 then return nil end
  hasil[1].mulaiMs = 0
  hasil[#hasil].akhirMs = batas
  for i = 2, #hasil do
    if hasil[i].mulaiMs > hasil[i - 1].akhirMs then hasil[i].mulaiMs = hasil[i - 1].akhirMs end
  end
  return hasil
end

local function analisisOffline(item, lapor, denganPeta, status)
  local dur = durasiLagu(item.path)
  if dur < 12 then return nil, "Lagu terlalu pendek untuk dianalisis" end
  local waktu = { dekode = 0, nada = 0, tempo = 0, peta = 0 }
  status.waktu = waktu
  local kroma = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  local semuaW = {}
  local petaChunk = {}
  local daftarChord = {}
  local posisi = 0
  local panjangChunk = 20
  local totalChunk = math.ceil((dur - 1) / panjangChunk)
  local skalaChunk = 95
  if denganPeta then skalaChunk = 80 end
  local i = 1
  while posisi < dur do
    local pjg = math.min(panjangChunk, dur - posisi)
    if pjg < 5 then break end
    if DJL.batal then return nil, "Dibatalkan" end
    lapor("Membuka bagian lagu " .. i .. " dari " .. totalChunk, (i - 1) / totalChunk * skalaChunk)
    local t0 = jamMs()
    local x, fs, awalNyata = dekodeJendela(item.path, posisi, pjg)
    waktu.dekode = waktu.dekode + (jamMs() - t0)
    if x and #x > 10000 then
      lapor("Menghitung nada bagian " .. i .. " dari " .. totalChunk, (i - 1 + 0.35) / totalChunk * skalaChunk)
      local kc = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
      t0 = jamMs()
      D.tambahChroma(x, fs, kc, daftarChord, awalNyata)
      waktu.nada = waktu.nada + (jamMs() - t0)
      for q = 1, 12 do kroma[q] = kroma[q] + kc[q] end
      if DJL.batal then return nil, "Dibatalkan" end
      lapor("Menghitung tempo bagian " .. i .. " dari " .. totalChunk, (i - 1 + 0.6) / totalChunk * skalaChunk)
      t0 = jamMs()
      local w = D.hitungOnset(x, fs)
      waktu.tempo = waktu.tempo + (jamMs() - t0)
      if w then
        if denganPeta then
          petaChunk[#petaChunk + 1] = { f = w.f, n = w.n, hopSec = w.hopSec, ofsSec = w.ofsSec, awal = awalNyata, kroma = kc }
        end
        D.olahOnset(w)
        w.awal = awalNyata
        semuaW[#semuaW + 1] = w
      end
    end
    x = nil
    collectgarbage()
    posisi = posisi + pjg
    i = i + 1
  end
  if DJL.batal then return nil, "Dibatalkan" end
  if #semuaW == 0 then return nil, "Tempo tidak bisa dihitung dari lagu ini" end
  lapor("Menyimpulkan hasil", skalaChunk + 2)
  local t1 = jamMs()
  local hasil, galat = D.analisisInti(semuaW, kroma)
  waktu.tempo = waktu.tempo + (jamMs() - t1)
  if not hasil then return nil, galat end
  local rangkaian = {}
  table.sort(daftarChord, function(a, b) return a.mulai < b.mulai end)
  for _, c in ipairs(daftarChord) do
    local terakhir = rangkaian[#rangkaian]
    if terakhir and terakhir.nama == c.nama and c.mulai <= terakhir.akhir + 0.35 then
      local durasiLama = math.max(0.01, terakhir.akhir - terakhir.mulai)
      local durasiBaru = math.max(0.01, c.akhir - c.mulai)
      terakhir.akhir = math.max(terakhir.akhir, c.akhir)
      terakhir.skor = (terakhir.skor * durasiLama + c.skor * durasiBaru) / (durasiLama + durasiBaru)
      terakhir.keyakinan = math.max(terakhir.keyakinan or 0, c.keyakinan or 0)
    else
      rangkaian[#rangkaian + 1] = {
        nama = c.nama,
        akar = c.akar,
        kualitas = c.kualitas,
        nada = c.nada,
        bass = c.bass,
        keyakinan = c.keyakinan,
        mulai = c.mulai,
        akhir = c.akhir,
        skor = c.skor
      }
    end
  end
  hasil.chord = rangkaian
  hasil.chordv = 3
  status.hasil = hasil
  local peta = nil
  if denganPeta and #petaChunk > 0 then
    lapor("Menyusun peta tempo", 85)
    local t2 = jamMs()
    local p, pesanPeta = D.buatPeta(petaChunk, dur, lapor)
    waktu.peta = jamMs() - t2
    if p then
      peta = D.validasiPeta(p, dur)
      if not peta then DJL.catatan = "Peta tempo tidak memiliki bagian yang valid." end
    else
      DJL.catatan = "Peta tempo tidak bisa dibuat: " .. tostring(pesanPeta)
    end
  end
  return hasil, nil, peta
end

local function namaSingkat(penyedia)
  return NAMA_PENYEDIA[penyedia] or "FreqBlog"
end

local function teksOnline(penyedia)
  if penyedia == "audo" then
    if pengaturan.tokenAudo ~= "" then return "Audo AI, memakai kunci" end
    return "Audo AI, gratis tanpa kunci, jatah 20 per hari"
  end
  return "FreqBlog, kuota gratis 25 per bulan"
end

local function kunciKosong(penyedia)
  if penyedia == "freqblog" then return pengaturan.token == "" end
  return false
end

local function tampilProgres(judul, teks, saatBatal)
  local d = dialogBaru(judul)
  d.setMessage(teks)
  d.setCancelable(false)
  d.setButton("Batal", function() if saatBatal then saatBatal() end end)
  DJL.dlgProgres = d
  DJL.teksProgres = nil
  DJL.waktuProgres = 0
  bukaDialog(d)
end

local function perbaruiProgres(teks)
  DJL.progresBaru = teks
end

terapkanProgres = function()
  local pesanToast = DJL.toastProgres
  DJL.toastProgres = nil
  if pesanToast then toast(pesanToast) end
  local teks = DJL.progresBaru
  if teks == nil then return end
  if teks == DJL.teksProgres then
    DJL.progresBaru = nil
    return
  end
  local sekarang = System.currentTimeMillis()
  if sekarang - (DJL.waktuProgres or 0) < 250 then return end
  DJL.progresBaru = nil
  DJL.teksProgres = teks
  DJL.waktuProgres = sekarang
  jalankanUI(function()
    local d = DJL.dlgProgres
    if d and DJL.dlg == d then pcall(function() d.setMessage(teks) end) end
  end)
end

local function lapor(teks, persen)
  local p = nil
  if persen then
    p = math.floor(persen)
    if p > 100 then p = 100 end
    if p < 0 then p = 0 end
  end
  local t = teks
  if p then
    t = teks .. ", " .. tostring(p) .. " persen"
    if p >= (DJL.umumPersen or 25) and p < 100 then
      DJL.umumPersen = (math.floor(p / 25) + 1) * 25
      DJL.toastProgres = tostring(p) .. " persen"
    end
  end
  perbaruiProgres(t)
end

local function objekAnalisis(o)
  if o == nil then return nil end
  local d = nil
  pcall(function() d = o.optJSONObject("data") end)
  if d ~= nil then return d end
  pcall(function() d = o.optJSONObject("result") end)
  if d ~= nil then return d end
  return o
end

local function angkaJSON(o, nama, cadangan)
  local v = 0
  pcall(function() v = o.optDouble(nama, 0) end)
  if v <= 0 and cadangan then
    for _, k in ipairs(cadangan) do
      pcall(function() if v <= 0 then v = o.optDouble(k, 0) end end)
    end
  end
  return v
end

local function uraikanFreq(kode, isi)
  local ok, akar = pcall(function() return buatJava("org.json.JSONObject", isi) end)
  if kode ~= 200 then
    local kd, rinci = "", string.sub(isi, 1, 180)
    if ok and akar ~= nil then
      kd = tostring(akar.optString("error_code"))
      local dt = tostring(akar.optString("detail"))
      if dt ~= "" then rinci = string.sub(dt, 1, 180) end
    end
    local pesan = "Kesalahan dari FreqBlog."
    if kode == 401 then pesan = "Kunci FreqBlog ditolak. Periksa kunci di pengaturan."
    elseif kode == 402 then pesan = "Kuota gratis FreqBlog bulan ini habis."
    elseif kode == 413 then pesan = "Berkas lebih dari 15 MB."
    elseif kode == 415 then pesan = "Berkas tidak bisa dibaca sebagai audio."
    elseif kode == 429 then pesan = "Terlalu banyak permintaan atau kuota habis."
    elseif kode == 504 then pesan = "Analisis kehabisan waktu. Coba lagi." end
    return { galat = pesan .. " Kode " .. tostring(kode) .. " " .. kd .. ". " .. rinci }
  end
  if not ok or akar == nil then return { galat = "Balasan FreqBlog tidak terbaca. " .. string.sub(isi, 1, 180) } end
  local o = objekAnalisis(akar)
  local bpm = angkaJSON(o, "bpm", { "tempo", "bpm_snapped" })
  if bpm <= 0 then return { galat = "FreqBlog tidak mengembalikan angka BPM yang valid. " .. string.sub(isi, 1, 180) } end
  local kunci = tostring(o.optString("key"))
  if kunci == "" or kunci == "null" then kunci = tostring(o.optString("musical_key")) end
  return {
    sumber = "FreqBlog", bpm = bpm,
    yakinBpm = angkaJSON(o, "bpm_confidence", { "tempo_confidence" }),
    kunci = kunci,
    yakinKunci = angkaJSON(o, "key_confidence", { "confidence" }),
    camelot = tostring(o.optString("camelot")),
    seg = angkaJSON(o, "representative_segment_start", { "segment_start" })
  }
end

local function uraikanAudo(kode, isi)
  if kode ~= 200 then
    local pesan
    if kode == 401 or kode == 403 then
      pesan = "Kunci Audo AI ditolak. Periksa kunci di pengaturan."
    elseif kode == 402 then
      pesan = "Kredit Audo AI tidak cukup."
    elseif kode == 413 then
      pesan = "Berkas terlalu besar untuk Audo AI."
    elseif kode == 415 then
      pesan = "Berkas tidak bisa dibaca sebagai audio."
    elseif kode == 429 then
      pesan = "Jatah atau laju Audo AI habis. Coba lagi nanti."
    else
      pesan = "Kesalahan dari Audo AI."
    end
    return { galat = pesan .. " Kode " .. tostring(kode) .. ". " .. string.sub(isi, 1, 150) }
  end
  local ok, akar = pcall(function() return buatJava("org.json.JSONObject", isi) end)
  if not ok or akar == nil then
    return { galat = "Balasan Audo AI tidak terbaca. " .. string.sub(isi, 1, 180) }
  end
  local o = objekAnalisis(akar)
  local bpm = angkaJSON(o, "bpm", { "tempo", "bpm_snapped" })
  if bpm <= 0 then return { galat = "Audo AI tidak mengembalikan tempo yang valid. " .. string.sub(isi, 1, 180) } end
  local kunci = tostring(o.optString("key"))
  if kunci == "" or kunci == "null" then
    kunci = tostring(o.optString("tonic")) .. " " .. tostring(o.optString("mode"))
  end
  local lain = {}
  pcall(function()
    local arr = o.optJSONArray("other_keys")
    if arr ~= nil then
      for i = 0, arr.length() - 1 do
        local k = arr.optJSONObject(i)
        if k ~= nil then
          lain[#lain + 1] = tostring(k.optString("key")) .. " (" .. angka(k.optDouble("confidence", 0), 2) .. ")"
        end
      end
    end
  end)
  return {
    sumber = "Audo AI",
    bpm = bpm,
    yakinBpm = angkaJSON(o, "bpm_confidence", { "tempo_confidence" }),
    kunci = kunci,
    yakinKunci = angkaJSON(o, "key_confidence", { "confidence" }),
    camelot = tostring(o.optString("camelot")),
    lain = table.concat(lain, ", "),
    seg = 0
  }
end

local function unggahBerkas(alamat, tajuk, path, info, opsi)
  local file = buatJava("java.io.File", path)
  local total = file.length()
  local ekst = string.lower(string.match(path, "%.(%w+)$") or "mp3")
  local batas = "----DJLUnggah" .. tostring(os.time())
  local conn = buatJava("java.net.URL", alamat).openConnection()
  DJL.sambungan = conn
  conn.setConnectTimeout(opsi.konek)
  conn.setReadTimeout(opsi.baca)
  conn.setRequestMethod("POST")
  conn.setDoOutput(true)
  if opsi.bertahap then conn.setChunkedStreamingMode(65536) end
  for k, v in pairs(tajuk) do conn.setRequestProperty(k, v) end
  conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" .. batas)
  local out = buatJava("java.io.DataOutputStream", conn.getOutputStream())
  out.writeBytes("--" .. batas .. "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"lagu." .. ekst .. "\"\r\nContent-Type: application/octet-stream\r\n\r\n")
  local masuk = buatJava("java.io.FileInputStream", file)
  local buf = larik("Byte", 16384)
  local terkirim, terakhir = 0, -1
  while true do
    if DJL.batalOnline then
      masuk.close()
      error("Dibatalkan", 0)
    end
    local n = masuk.read(buf)
    if n <= 0 then break end
    out.write(buf, 0, n)
    terkirim = terkirim + n
    if opsi.bertahap and total > 0 then
      local p = math.floor(terkirim * 100 / total)
      if p ~= terakhir then
        terakhir = p
        info("Mengunggah ke " .. opsi.nama .. ", " .. tostring(p) .. " persen")
      end
    end
    napas()
  end
  masuk.close()
  out.writeBytes("\r\n--" .. batas .. "--\r\n")
  out.flush()
  out.close()
  return conn
end

local function kirimFreq(token, path, info)
  local file = buatJava("java.io.File", path)
  if not file.exists() then return { galat = "Berkas lagu tidak ditemukan" } end
  if file.length() > BATAS_UNGGAH then
    return { galat = "Berkas lebih dari 15 MB, tidak bisa diunggah ke FreqBlog. Pakai analisis offline." }
  end
  info("Mengunggah ke FreqBlog")
  local conn = unggahBerkas("https://api.freqblog.com/analyze", { ["X-Api-Key"] = token }, path, info, { konek = 15000, baca = 90000, bertahap = false, nama = "FreqBlog" })
  info("Menunggu hasil dari FreqBlog")
  local kode, isi = bacaTanggapan(conn)
  DJL.sambungan = nil
  return uraikanFreq(kode, isi)
end

local function cariTautanJob(isi)
  local t = string.gsub(isi, "\\u0026", "&")
  t = string.gsub(t, "\\/", "/")
  local p = string.match(t, "https://audo%.ai/api/try/jobs/[^\"%s<>]+")
  if p then return p end
  local r = string.match(t, "/api/try/jobs/[^\"%s<>]+")
  if r then return "https://audo.ai" .. r end
  return nil
end

local function cekJobAudo(tautan, tajuk)
  local conn = buatJava("java.net.URL", tautan).openConnection()
  DJL.sambungan = conn
  conn.setConnectTimeout(20000)
  conn.setReadTimeout(60000)
  conn.setRequestMethod("GET")
  for k, v in pairs(tajuk) do conn.setRequestProperty(k, v) end
  local kode, isi = bacaTanggapan(conn)
  DJL.sambungan = nil
  return kode, isi
end

local function kirimAudo(token, path, info)
  local file = buatJava("java.io.File", path)
  if not file.exists() then return { galat = "Berkas lagu tidak ditemukan" } end
  if file.length() > BATAS_AUDO then
    return { galat = "Berkas lebih dari 95 MB, tidak bisa diunggah ke Audo AI. Pakai analisis offline." }
  end
  local tajuk = { ["User-Agent"] = "DJL-tempo-chord-jieshuo" }
  if token ~= "" then tajuk["Authorization"] = "Bearer " .. token end
  info("Mengunggah ke Audo AI")
  local conn = unggahBerkas(ALAMAT_AUDO, tajuk, path, info, { konek = 20000, baca = 120000, bertahap = true, nama = "Audo AI" })
  info("Menunggu hasil dari Audo AI")
  local kode, isi = bacaTanggapan(conn)
  DJL.sambungan = nil
  local n = 0
  while kode == 202 and n < 40 and not DJL.batalOnline do
    local tautan = cariTautanJob(isi)
    if not tautan or string.sub(tautan, 1, 16) ~= "https://audo.ai/" then break end
    n = n + 1
    info("Menunggu hasil dari Audo AI, pengecekan ke-" .. tostring(n))
    jeda(3000)
    if DJL.batalOnline then break end
    local ok, k2, i2 = lindungi(cekJobAudo, tautan, tajuk)
    if not ok then return { galat = "Tidak bisa mengecek hasil Audo AI. " .. tostring(k2) } end
    kode, isi = k2, i2
  end
  if DJL.batalOnline then error("Dibatalkan", 0) end
  if kode == 202 then return { galat = "Audo AI belum selesai memproses. Coba lagi nanti." } end
  return uraikanAudo(kode, isi)
end

local function kirimOnline(penyedia, path, info)
  if penyedia == "freqblog" then return kirimFreq(pengaturan.token, path, info) end
  return kirimAudo(pengaturan.tokenAudo, path, info)
end

local function batalkanUnggah()
  DJL.batalOnline = true
  local conn = DJL.sambungan
  if conn then
    latar(function() pcall(function() conn.disconnect() end) end)
  end
end

local function yakinKunciOffline(s1, s2)
  if s1 >= 0.75 and s1 - s2 >= 0.05 then return "tinggi" end
  if s1 >= 0.6 then return "sedang" end
  return "rendah"
end

local function yakinTempoOffline(o)
  local r = o.rasio or 0
  if o.v == 2 then
    if r >= 9 then return "tinggi" end
    if r >= 6.4 then return "sedang" end
    return "rendah"
  end
  if r >= 2.5 then return "tinggi" end
  if r >= 1.6 then return "sedang" end
  return "rendah"
end

local function teksPeta(peta, geser)
  geser = geser or 0
  if #peta == 1 and peta[1].tipe == "tetap" then
    local satu = "Peta tempo: tempo tampak tetap sepanjang lagu, sekitar " .. angka(peta[1].bpm, 1) .. " BPM."
    if peta[1].pc then satu = satu .. " Kunci " .. namaKunciGeser(peta[1].pc, peta[1].mode, geser) .. "." end
    return satu
  end
  local b = { "Peta tempo sepanjang lagu, " .. #peta .. " bagian:" }
  for i, p in ipairs(peta) do
    local baris = "Bagian " .. i .. ", " .. waktuTeks(p.mulaiMs) .. " sampai " .. waktuTeks(p.akhirMs) .. ", "
    if p.tipe == "bertahap" then
      local arah = "naik"
      if p.bpm2 < p.bpm then arah = "turun" end
      baris = baris .. arah .. " bertahap dari " .. angka(p.bpm, 1) .. " ke " .. angka(p.bpm2, 1) .. " BPM."
    else
      baris = baris .. "tetap, sekitar " .. angka(p.bpm, 1) .. " BPM."
    end
    if p.pc then baris = baris .. " Kunci " .. namaKunciGeser(p.pc, p.mode, geser) .. "." end
    b[#b + 1] = baris
  end
  return table.concat(b, "\n")
end

local function teksRingkasHasil(item)
  local h = ambilHasil(item)
  local geser = ambilTranspose(item)
  local b = { "Analisis selesai untuk lagu: " .. item.nama, "" }
  if geser ~= 0 then b[#b + 1] = "Tampilan transpose " .. tostring(geser) .. " semiton; audio tetap asli." end
  b[#b + 1] = "Hasil tempo: " .. ((h.off or h.on or h.fix or h.peta) and "tersedia" or "belum tersedia")
  b[#b + 1] = "Hasil nada dasar: " .. ((h.off or h.on or h.peta) and "tersedia" or "belum tersedia")
  local daftar = h.off and h.off.chord or {}
  b[#b + 1] = "Hasil chord offline: " .. ((daftar and #daftar > 0) and (tostring(#daftar) .. " bagian") or "belum tersedia")
  b[#b + 1] = "Buka Menu hasil untuk membaca atau menyalin setiap bagian secara terpisah."
  return table.concat(b, "\n")
end

local function susunTeks(item)
  local h = ambilHasil(item)
  local geser = ambilTranspose(item)
  local b = {}
  if geser ~= 0 then b[#b + 1] = "Transpose tampilan " .. tostring(geser) .. " semiton; audio tetap asli." end
  b[#b + 1] = "Lagu: " .. item.nama
  if h.off then
    local o = h.off
    b[#b + 1] = "Offline: tempo " .. angka(o.bpm, 1) .. " BPM, alternatif " .. angka(o.bpm / 2, 1) .. " atau " .. angka(o.bpm * 2, 1) .. ", keyakinan " .. yakinTempoOffline(o) .. "."
    b[#b + 1] = "Kunci offline: " .. namaKunciGeser(o.pc1, o.mode1, geser) .. ", kemungkinan kedua " .. namaKunciGeser(o.pc2, o.mode2, geser) .. ", keyakinan " .. yakinKunciOffline(o.skor1, o.skor2) .. "."
  end
  local nm = "FreqBlog"
  if h.on then
    local o = h.on
    nm = tostring(o.sumber or "FreqBlog")
    local pc, md = uraiKunci(o.kunci)
    local nk = tostring(o.kunci)
    if pc then nk = namaKunciGeser(pc, md, geser) end
    local desimalTempo = 1
    if nm == "Audo AI" then desimalTempo = 2 end
    b[#b + 1] = nm .. ": tempo " .. angka(o.bpm, 1) .. " BPM, keyakinan " .. angka(o.yakinBpm, desimalTempo) .. "."
    b[#b + 1] = "Kunci " .. nm .. ": " .. nk .. ", keyakinan " .. angka(o.yakinKunci, 2) .. ", Camelot " .. tostring(o.camelot) .. "."
    if o.lain and tostring(o.lain) ~= "" then
      b[#b + 1] = "Kemungkinan kunci lain dari " .. nm .. ": " .. tostring(o.lain) .. "."
    end
  end
  if h.off and h.on then
    local r = h.off.bpm / h.on.bpm
    if math.abs(r - 1) < 0.03 then
      b[#b + 1] = "Tempo offline dan " .. nm .. " cocok."
    elseif math.abs(r - 2) < 0.06 or math.abs(r - 0.5) < 0.03 then
      b[#b + 1] = "Tempo offline dan " .. nm .. " selisih satu oktaf, dua kali atau setengah. Periksa dengan metronom."
    else
      b[#b + 1] = "Tempo offline dan " .. nm .. " berbeda. Periksa dengan metronom."
    end
    local pc, md = uraiKunci(h.on.kunci)
    if pc then
      if pc == h.off.pc1 and md == h.off.mode1 then
        b[#b + 1] = "Kunci offline dan " .. nm .. " cocok."
      elseif pc == h.off.pc2 and md == h.off.mode2 then
        b[#b + 1] = "Kunci " .. nm .. " sama dengan kemungkinan kedua offline."
      else
        b[#b + 1] = "Kunci offline dan " .. nm .. " berbeda. Periksa dengan akor."
      end
    end
  end
  if h.peta then b[#b + 1] = teksPeta(h.peta, geser) end
  if h.fix then b[#b + 1] = "Tempo yang sudah kamu periksa: " .. angka(h.fix, 1) .. " BPM." end
  if DJL.catatan then b[#b + 1] = DJL.catatan end
  if not h.off and not h.on and not h.peta then b[#b + 1] = "Belum ada hasil analisis." end
  return table.concat(b, "\n")
end

function SM.bacaWav(path)
  local f = buatJava("java.io.File", path)
  local panjang = f.length()
  if panjang < 48 or panjang > 12 * 1048576 then return nil, "Ukuran berkas WAV tidak sesuai" end
  local buf = larik("Byte", panjang)
  local masuk = buatJava("java.io.FileInputStream", f)
  local total = 0
  while total < panjang do
    local n = masuk.read(buf, total, panjang - total)
    if n <= 0 then break end
    total = total + n
  end
  masuk.close()
  local function by(i)
    local v = buf[i]
    if v < 0 then v = v + 256 end
    return math.floor(v)
  end
  local function u16(i) return by(i) + by(i + 1) * 256 end
  local function u32(i) return by(i) + by(i + 1) * 256 + by(i + 2) * 65536 + by(i + 3) * 16777216 end
  local function teks4(i) return string.char(by(i), by(i + 1), by(i + 2), by(i + 3)) end
  if teks4(0) ~= "RIFF" or teks4(8) ~= "WAVE" then return nil, "Bukan berkas WAV" end
  local pos = 12
  local fmtTag, kanal, sr, bits = nil, 1, 44100, 16
  local dataMulai, dataUkuran = nil, 0
  while pos + 8 <= total do
    local id = teks4(pos)
    local ukuran = u32(pos + 4)
    local isi = pos + 8
    if id == "fmt " then
      fmtTag = u16(isi)
      kanal = u16(isi + 2)
      sr = u32(isi + 4)
      bits = u16(isi + 14)
      if fmtTag == 65534 and ukuran >= 26 then fmtTag = u16(isi + 24) end
    elseif id == "data" then
      dataMulai = isi
      dataUkuran = ukuran
      if dataMulai + dataUkuran > total then dataUkuran = total - dataMulai end
      break
    end
    pos = isi + ukuran + (ukuran % 2)
  end
  if not dataMulai or not fmtTag then return nil, "Struktur berkas WAV tidak dikenali" end
  if kanal < 1 or kanal > 8 or sr < 4000 then return nil, "Parameter berkas WAV tidak wajar" end
  local bps = math.floor(bits / 8)
  local frameUkuran = bps * kanal
  local jmlFrame = math.floor(dataUkuran / frameUkuran)
  local maks = math.floor(sr * 1.5)
  if jmlFrame > maks then jmlFrame = maks end
  local Float = luajava.bindClass("java.lang.Float")
  local hasil = {}
  for fr = 0, jmlFrame - 1 do
    local s = 0
    for c = 0, kanal - 1 do
      local i = dataMulai + fr * frameUkuran + c * bps
      local v
      if fmtTag == 3 and bits == 32 then
        local b = u32(i)
        if b >= 2147483648 then b = b - 4294967296 end
        v = Float.intBitsToFloat(b)
      elseif bits == 16 then
        v = u16(i)
        if v >= 32768 then v = v - 65536 end
        v = v / 32768
      elseif bits == 8 then
        v = (by(i) - 128) / 128
      elseif bits == 24 then
        v = by(i) + by(i + 1) * 256 + by(i + 2) * 65536
        if v >= 8388608 then v = v - 16777216 end
        v = v / 8388608
      elseif bits == 32 then
        local b = u32(i)
        if b >= 2147483648 then b = b - 4294967296 end
        v = b / 2147483648
      else
        return nil, "Format WAV " .. tostring(bits) .. " bit belum didukung"
      end
      s = s + v
    end
    hasil[fr + 1] = s / kanal
    if fr % 600 == 0 then napas() end
  end
  return hasil, sr
end

function SM.dekode(path)
  local ext = buatJava("android.media.MediaExtractor")
  ext.setDataSource(path)
  local jalur = -1
  local format = nil
  for i = 0, ext.getTrackCount() - 1 do
    local f = ext.getTrackFormat(i)
    local mime = tostring(f.getString("mime"))
    if string.sub(mime, 1, 6) == "audio/" then
      jalur = i
      format = f
      break
    end
  end
  if jalur < 0 then
    ext.release()
    return nil, "Berkas ini bukan audio"
  end
  ext.selectTrack(jalur)
  local mime = tostring(format.getString("mime"))
  local sr = 44100
  local kanal = 2
  pcall(function() sr = format.getInteger("sample-rate") end)
  pcall(function() kanal = format.getInteger("channel-count") end)
  local codec = luajava.bindClass("android.media.MediaCodec").createDecoderByType(mime)
  codec.configure(format, nil, nil, 0)
  codec.start()
  local info = buatJava("android.media.MediaCodec$BufferInfo")
  local hasil = {}
  local nh = 0
  local maks = math.floor(1.5 * sr)
  local selesaiMasuk = false
  local selesaiKeluar = false
  local kapasitas = 8192
  local pendek = larik("Short", kapasitas)
  local BO = luajava.bindClass("java.nio.ByteOrder")
  local putaran = 0
  while not selesaiKeluar and nh < maks do
    putaran = putaran + 1
    if putaran > 20000 then break end
    if not selesaiMasuk then
      local ix = codec.dequeueInputBuffer(10000)
      if ix >= 0 then
        local buf = codec.getInputBuffer(ix)
        local n = ext.readSampleData(buf, 0)
        if n < 0 then
          codec.queueInputBuffer(ix, 0, 0, 0, 4)
          selesaiMasuk = true
        else
          codec.queueInputBuffer(ix, 0, n, ext.getSampleTime(), 0)
          ext.advance()
        end
      end
    end
    local ox = codec.dequeueOutputBuffer(info, 10000)
    if ox >= 0 then
      local ob = codec.getOutputBuffer(ox)
      local ukuran = info.size
      if ukuran > 0 then
        ob.position(info.offset)
        ob.limit(info.offset + ukuran)
        local sb = ob.order(BO.LITTLE_ENDIAN).asShortBuffer()
        local jumlah = math.floor(ukuran / 2)
        if jumlah > kapasitas then
          kapasitas = jumlah
          pendek = larik("Short", kapasitas)
        end
        sb.get(pendek, 0, jumlah)
        local frames = math.floor(jumlah / kanal)
        for fr = 0, frames - 1 do
          if nh >= maks then break end
          local s = 0
          for c = 0, kanal - 1 do s = s + pendek[fr * kanal + c] end
          nh = nh + 1
          hasil[nh] = s / kanal / 32768
        end
      end
      codec.releaseOutputBuffer(ox, false)
      if math.floor(info.flags / 4) % 2 == 1 then selesaiKeluar = true end
      napas()
    elseif ox == -2 then
      local of = codec.getOutputFormat()
      pcall(function() sr = of.getInteger("sample-rate") end)
      pcall(function() kanal = of.getInteger("channel-count") end)
    end
  end
  pcall(function() codec.stop() end)
  pcall(function() codec.release() end)
  pcall(function() ext.release() end)
  return hasil, sr
end

function SM.olah(v, sr)
  if #v < 16 then return nil, "Sampel terlalu pendek" end
  local mono = v
  if sr ~= LAJU then
    mono = {}
    local m = math.floor(#v * LAJU / sr)
    for i = 1, m do
      local pos = (i - 1) * sr / LAJU
      local i0 = math.floor(pos)
      local fr = pos - i0
      local a = v[i0 + 1] or 0
      local b = v[i0 + 2] or a
      mono[i] = a * (1 - fr) + b * fr
      if i % 2000 == 0 then napas() end
    end
  end
  local puncak = 0
  for i = 1, #mono do
    local a = math.abs(mono[i])
    if a > puncak then puncak = a end
  end
  if puncak < 1e-4 then return nil, "Sampel kosong atau terlalu pelan" end
  local mulai = 1
  for i = 1, #mono do
    if math.abs(mono[i]) >= 0.15 * puncak then
      mulai = i
      break
    end
  end
  mulai = math.max(1, mulai - math.floor(0.002 * LAJU))
  local akhir = math.min(#mono, mulai + math.floor(0.6 * LAJU) - 1)
  local pjg = akhir - mulai + 1
  local pudar = math.floor(0.005 * LAJU)
  local k = {}
  for i = 1, pjg do
    local a = mono[mulai + i - 1] / puncak
    local sisa = pjg - i
    if sisa < pudar then a = a * sisa / pudar end
    k[i] = math.floor(a * 30000)
    if i % 2000 == 0 then napas() end
  end
  local info = { srAsli = sr, durAsliMs = math.floor(#v * 1000 / sr), durPakaiMs = math.floor(pjg * 1000 / LAJU), puncak = puncak }
  return k, info
end

function SM.muat(path)
  local f = buatJava("java.io.File", path)
  if not f.exists() then return nil, "Berkas tidak ditemukan" end
  local ekst = string.lower(string.match(path, "%.(%w+)$") or "")
  local v, sr
  if ekst == "wav" then
    local a, b = SM.bacaWav(path)
    if a then
      v = a
      sr = b
    end
  end
  if not v then
    v, sr = SM.dekode(path)
    if not v then return nil, sr end
  end
  return SM.olah(v, sr)
end

function SM.cache(slot)
  local path = pengaturan[slot]
  if path == nil or path == "" then return nil end
  DJL.sampel = DJL.sampel or {}
  local c = DJL.sampel[slot]
  if c and c.path == path then return c.data, c.info end
  local data, info = SM.muat(path)
  if data then
    DJL.sampel[slot] = { path = path, data = data, info = info }
    return data, info
  end
  DJL.galatSampel = tostring(info)
  return nil
end

function SM.klik(aksen)
  local rendah = SM.cache("sampel")
  local tinggi = SM.cache("sampelAksen")
  local data
  if aksen then data = tinggi or rendah else data = rendah or tinggi end
  if not data then return nil end
  local gain = 1
  if not aksen and (rendah == nil or tinggi == nil) and (tonumber(pengaturan.birama) or 0) > 0 then gain = 0.8 end
  local k = {}
  for i = 1, #data do
    k[i] = math.floor(data[i] * gain)
    if i % 2000 == 0 then napas() end
  end
  return k
end

function SM.salin(path, slot)
  local hasil = path
  pcall(function()
    local sumber = File(path)
    if sumber.length() > 12 * 1048576 then return end
    local ekst = string.lower(string.match(path, "%.(%w+)$") or "dat")
    local tujuan = File(ctx.getFilesDir(), "metronom_" .. slot .. "." .. ekst)
    local masuk = FileInputStream(sumber)
    local keluar = FileOutputStream(tujuan)
    local buf = larik("Byte", 8192)
    while true do
      local n = masuk.read(buf)
      if n <= 0 then break end
      keluar.write(buf, 0, n)
    end
    keluar.close()
    masuk.close()
    hasil = tostring(tujuan.getAbsolutePath())
  end)
  return hasil
end

local function jumlahBirama()
  local b = tonumber(pengaturan.birama) or 0
  if b < 2 then return 1 end
  return b
end

local function teksBirama()
  local b = jumlahBirama()
  if b < 2 then return "tanpa aksen, semua ketukan sama" end
  return tostring(b) .. " ketukan per birama, satu tinggi dan sisanya rendah"
end

local function daftarBunyiAktif()
  local d = {}
  for _, v in ipairs(DAFTAR_BUNYI) do d[#d + 1] = v end
  if pengaturan.sampel ~= "" or pengaturan.sampelAksen ~= "" then d[#d + 1] = "sampel" end
  return d
end

function MT.klikTabel(jenis, aksen)
  local k = {}
  if jenis == "tiruan" then
    local n = math.floor(0.06 * LAJU)
    local fr = 1400
    local amp = 0.78
    if aksen then
      fr = 2100
      amp = 0.95
    end
    local pudar = math.floor(0.004 * LAJU)
    for i = 1, n do
      local t = (i - 1) / LAJU
      local naik = math.min(1, t / 0.0006)
      local v = (math.sin(2 * math.pi * fr * t) + 0.12 * math.sin(4 * math.pi * fr * t)) * math.exp(-t * 55) * naik
      local sisa = n - i
      if sisa < pudar then v = v * sisa / pudar end
      k[i] = math.floor(v * amp * 29000)
    end
    return k
  end
  local n = math.floor(0.04 * LAJU)
  local amp = 0.7
  if aksen then amp = 0.95 end
  for i = 1, n do
    local t = (i - 1) / LAJU
    local v
    if jenis == "klik" then
      v = (math.random() * 2 - 1) * math.exp(-t * 250)
    elseif jenis == "bip" then
      local fr = 1000
      if aksen then fr = 1500 end
      v = math.sin(2 * math.pi * fr * t) * math.exp(-t * 60)
    else
      local fr = 900
      if aksen then fr = 1300 end
      v = math.sin(2 * math.pi * fr * t) * math.exp(-t * 90)
    end
    k[i] = math.floor(v * amp * 32000)
  end
  return k
end

function MT.dataValid(d)
  return type(d) == "table" and type(d.normal) == "table" and type(d.aksen) == "table" and type(d.nNormal) == "number" and type(d.nAksen) == "number" and d.nNormal > 0 and d.nAksen > 0
end

function MT.dariTabel(kNormal, kAksen)
  return { normal = kNormal, nNormal = #kNormal, aksen = kAksen, nAksen = #kAksen }
end

function MT.sintetis(jenis)
  return MT.dariTabel(MT.klikTabel(jenis, false), MT.klikTabel(jenis, true))
end

function MT.dekodeB64(teks, maks)
  local hasil, n = {}, 0
  local pos, panjang = 1, #teks
  while pos + 3 <= panjang and n < maks do
    local a, b, c, d = string.byte(teks, pos, pos + 3)
    local va, vb, vc, vd = INDEKS_B64[a], INDEKS_B64[b], INDEKS_B64[c], INDEKS_B64[d]
    if va == nil or vb == nil then break end
    local x = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
    n = n + 1
    hasil[n] = math.floor(x / 65536)
    if vc ~= nil then
      n = n + 1
      hasil[n] = math.floor(x / 256) % 256
      if vd ~= nil then
        n = n + 1
        hasil[n] = x % 256
      end
    end
    pos = pos + 4
    if pos % 4000 == 1 then napas() end
  end
  return hasil, n
end

function MT.wavKeLua(teks)
  if type(teks) ~= "string" or #teks < 200 or #teks % 4 ~= 0 then return nil, "base64 tidak valid" end
  if string.find(teks, "[^%w%+/=]") then return nil, "ada karakter base64 yang tidak valid" end
  local penuh = math.floor(#teks / 4) * 3
  local b, total = MT.dekodeB64(teks, 4096)
  local function by(i) return b[i + 1] or 0 end
  local function u16(i) return by(i) + by(i + 1) * 256 end
  local function u32(i) return by(i) + by(i + 1) * 256 + by(i + 2) * 65536 + by(i + 3) * 16777216 end
  local function teks4(i) return string.char(by(i), by(i + 1), by(i + 2), by(i + 3)) end
  if total < 64 or teks4(0) ~= "RIFF" or teks4(8) ~= "WAVE" then return nil, "bukan WAV" end
  local pos = 12
  local tag, kanal, sr, bits = nil, 0, 0, 0
  local data0, dataUkuran = nil, 0
  while pos + 8 <= total do
    local id = teks4(pos)
    local ukuran = u32(pos + 4)
    local isi = pos + 8
    if id == "fmt " then
      tag = u16(isi)
      kanal = u16(isi + 2)
      sr = u32(isi + 4)
      bits = u16(isi + 14)
      if tag == 65534 and ukuran >= 26 then tag = u16(isi + 24) end
    elseif id == "data" then
      data0 = isi
      dataUkuran = ukuran
      if data0 + dataUkuran > penuh then dataUkuran = penuh - data0 end
      break
    end
    pos = isi + ukuran + (ukuran % 2)
  end
  if not data0 or tag ~= 1 then return nil, "format WAV tidak didukung" end
  if sr ~= LAJU then return nil, "laju " .. tostring(sr) .. " Hz tidak didukung, harus " .. tostring(LAJU) end
  if (bits ~= 16 and bits ~= 24) or kanal < 1 or kanal > 2 then return nil, "hanya 16 atau 24 bit, mono atau stereo" end
  local bps = math.floor(bits / 8)
  local blok = kanal * bps
  local n = math.min(math.floor(0.15 * sr), math.floor(dataUkuran / blok))
  if n < 100 then return nil, "data suara terlalu pendek" end
  b, total = MT.dekodeB64(teks, data0 + n * blok + 8)
  if total < data0 + n * blok then return nil, "data WAV terpotong" end
  local nilai = {}
  local puncak = 1
  for i = 0, n - 1 do
    local p = data0 + i * blok
    local atas
    local v
    if bits == 24 then
      atas = by(p + 2)
      if atas >= 128 then atas = atas - 256 end
      v = atas * 65536 + by(p + 1) * 256 + by(p)
    else
      atas = by(p + 1)
      if atas >= 128 then atas = atas - 256 end
      v = atas * 256 + by(p)
    end
    nilai[i + 1] = v
    local a = v
    if a < 0 then a = -a end
    if a > puncak then puncak = a end
    if i % 2000 == 0 then napas() end
  end
  local gain = 0.9 * 32767 / puncak
  local fadeN = math.floor(0.002 * sr)
  local k = {}
  for i = 1, n do
    local v = nilai[i] * gain
    local sisa = n - i
    if sisa < fadeN then v = v * sisa / fadeN end
    k[i] = math.floor(v + 0.5)
    if i % 2000 == 0 then napas() end
  end
  return { tab = k, n = n }
end

function MT.dariCubase()
  local lokasi = DJL.base
  if not lokasi then return nil, "folder skrip tidak ditemukan" end
  local f, err = loadfile(lokasi .. "metronom.lua")
  if not f then return nil, "metronom.lua tidak bisa dibaca: " .. tostring(err) end
  local ok, data = pcall(f)
  if not ok or type(data) ~= "table" then return nil, "isi metronom.lua tidak valid" end
  local hi, e1 = MT.wavKeLua(data.hi)
  if not hi then return nil, "data hi, " .. tostring(e1) end
  local lo, e2 = MT.wavKeLua(data.lo)
  if not lo then return nil, "data lo, " .. tostring(e2) end
  data = nil
  collectgarbage()
  return { normal = lo.tab, nNormal = lo.n, aksen = hi.tab, nAksen = hi.n }
end

function MT.bangunData(jenis)
  if jenis == "cubase" then
    local d, pesan = MT.dariCubase()
    if d then return d end
    return MT.sintetis("tiruan"), "Bunyi Cubase tidak bisa dimuat, " .. tostring(pesan) .. ". Memakai bunyi Tiruan Cubase."
  end
  if jenis == "sampel" then
    local rendah = SM.cache("sampel")
    local tinggi = SM.cache("sampelAksen")
    if not rendah and not tinggi then return nil, DJL.galatSampel or "Sampel belum dipilih" end
    return MT.dariTabel(SM.klik(false), SM.klik(true))
  end
  return MT.sintetis(jenis)
end

function MT.kunciKlik()
  if pengaturan.bunyi == "sampel" then
    return "sampel|" .. pengaturan.sampel .. "|" .. pengaturan.sampelAksen
  end
  return pengaturan.bunyi
end

function MT.siap()
  return DJL.klik ~= nil and MT.dataValid(DJL.klik[MT.kunciKlik()])
end

function MT.siapkan(selesai)
  DJL.klik = DJL.klik or {}
  local kunci = MT.kunciKlik()
  local jenis = pengaturan.bunyi
  if MT.dataValid(DJL.klik[kunci]) then
    selesai(true)
    return
  end
  DJL.klik[kunci] = nil
  DJL.antreKlik = DJL.antreKlik or {}
  DJL.antreKlik[#DJL.antreKlik + 1] = selesai
  if DJL.siapJalan then return end
  DJL.siapJalan = true
  jalankanBertahap(function()
    return MT.bangunData(jenis)
  end, function(ok, data, pesan)
    DJL.siapJalan = false
    local antre = DJL.antreKlik
    DJL.antreKlik = {}
    local berhasil = ok and MT.dataValid(data)
    if berhasil then
      DJL.klik[kunci] = data
      if pesan then toast(pesan) end
    else
      tampilGalat("Bunyi gagal disiapkan", tostring(data or pesan))
    end
    for _, f in ipairs(antre) do aman(f)(berhasil) end
  end)
end

function MT.tempel(j, t, awal, dst, tujuan, jml)
  local ok = pcall(function() System.arraycopy(j, awal, dst, tujuan, jml) end)
  if ok then return end
  for i = 0, jml - 1 do dst[tujuan + i] = t[awal + i + 1] end
end

function MT.trackKlik(periodeMs, offsetMs, birama, volume)
  local data = DJL.klik and DJL.klik[MT.kunciKlik()]
  if not MT.dataValid(data) then return nil end
  local per = math.max(1000, math.floor(periodeMs * LAJU / 1000 + 0.5))
  local total = per * birama
  local ofs = math.floor(offsetMs * LAJU / 1000 + 0.5) % total
  local blok = larik("Short", total)
  local fadeN = math.floor(0.003 * LAJU)
  local pjgN = math.min(data.nNormal, per)
  local pjgA = math.min(data.nAksen, per)
  local jN = larik("Short", pjgN)
  for i = 1, pjgN do jN[i - 1] = data.normal[i] end
  local jA = larik("Short", pjgA)
  for i = 1, pjgA do jA[i - 1] = data.aksen[i] end
  for b = 0, birama - 1 do
    local jsrc, tsrc, n, pjg = jN, data.normal, data.nNormal, pjgN
    if birama > 1 and b == 0 then jsrc, tsrc, n, pjg = jA, data.aksen, data.nAksen, pjgA end
    local mulai = (ofs + b * per) % total
    local pertama = math.min(pjg, total - mulai)
    MT.tempel(jsrc, tsrc, 0, blok, mulai, pertama)
    if pjg > pertama then MT.tempel(jsrc, tsrc, pertama, blok, 0, pjg - pertama) end
    if n > per then
      for i = 0, fadeN - 1 do
        local idx = (mulai + pjg - 1 - i) % total
        blok[idx] = math.floor(blok[idx] * i / fadeN)
      end
    end
  end
  local tr = AudioTrack(3, LAJU, 4, 2, total * 2, 0)
  tr.write(blok, 0, total)
  tr.setLoopPoints(0, total, -1)
  pcall(function() tr.setVolume(volume) end)
  return tr
end

function MT.hentikanUji()
  if DJL.uji then
    pcall(function() DJL.uji.stop() end)
    pcall(function() DJL.uji.release() end)
    DJL.uji = nil
  end
end

function MT.mainkanUji(periode, birama)
  MT.siapkan(function(ok)
    if not ok then return end
    MT.hentikanUji()
    local tr = MT.trackKlik(periode, 0, birama, tonumber(pengaturan.volKlik) / 100)
    if not tr then
      toast("Bunyi gagal dibuat")
      return
    end
    DJL.uji = tr
    pcall(function() tr.play() end)
    tunda(math.floor(periode * birama * 2) + 50, function()
      if DJL.uji == tr then MT.hentikanUji() end
    end)
  end)
end

function MT.uji()
  local b = jumlahBirama()
  if b < 2 then b = 4 end
  MT.mainkanUji(500, b)
end

function MT.ujiTempo(bpm)
  local b = jumlahBirama()
  if b < 2 then b = 4 end
  MT.mainkanUji(60000 / bpm, b)
end

function MT.hentikan()
  if ps and ps.track then
    pcall(function() ps.track.stop() end)
    pcall(function() ps.track.release() end)
    ps.track = nil
  end
end

function MT.mulai()
  MT.hentikan()
  if not ps or not ps.metOn then return false end
  if not MT.siap() then
    toast("Menyiapkan bunyi metronom")
    MT.siapkan(function(ok)
      if ok and ps and ps.metOn then
        MT.mulai()
      elseif ps then
        ps.metOn = false
        if ps.segarkan then ps.segarkan() end
      end
    end)
    return true
  end
  local periode = 60000 / ps.tempo
  local geser = 0
  ps.metSinkron = false
  if ps.lagu and ps.player then
    local pos = 0
    pcall(function() pos = ps.player.getCurrentPosition() end)
    local bar = jumlahBirama()
    geser = (ps.t0 + ps.fase + ((ps.satuIdx or 0) % bar) * periode - pos) % (periode * bar)
    ps.metSinkron = true
  end
  local tr = MT.trackKlik(periode, geser, jumlahBirama(), tonumber(pengaturan.volKlik) / 100)
  if tr then
    ps.track = tr
    pcall(function() tr.play() end)
    return true
  end
  ps.metOn = false
  toast("Metronom gagal dibuat")
  return false
end

function MT.bersihkan()
  if not ps then return end
  MT.hentikan()
  if ps.player then
    pcall(function() ps.player.stop() end)
    pcall(function() ps.player.release() end)
  end
  ps = nil
end

function MT.akor(pc, mode)
  if DJL.akor then
    pcall(function() DJL.akor.stop() end)
    pcall(function() DJL.akor.release() end)
    DJL.akor = nil
  end
  local f0 = 130.813 * 2 ^ (pc / 12)
  local terts = 3
  if mode == 1 then terts = 4 end
  local nada = { f0 / 2, f0, f0 * 2 ^ (terts / 12), f0 * 2 ^ (7 / 12) }
  local n = math.floor(1.6 * LAJU_AKOR)
  jalankanBertahap(function()
    local blok = {}
    for i = 0, n - 1 do
      local t = i / LAJU_AKOR
      local amplop = math.exp(-t * 1.6) * math.min(1, t * 80)
      local v = 0
      for _, f in ipairs(nada) do v = v + math.sin(2 * math.pi * f * t) end
      blok[i + 1] = math.floor(v / 4 * amplop * 26000)
      if i % 500 == 0 then napas() end
    end
    return blok
  end, function(ok, blok)
    if not ok or blok == nil then
      tampilGalat("Akor gagal dibuat", tostring(blok))
      return
    end
    local arr = larik("Short", n)
    for i = 1, n do arr[i - 1] = blok[i] end
    local tr = AudioTrack(3, LAJU_AKOR, 4, 2, n * 2, 0)
    tr.write(arr, 0, n)
    tr.play()
    DJL.akor = tr
  end)
end

local function hitungKetukan(w)
  local n = #w
  if n < 3 then return nil end
  local urut = {}
  for i = 2, n do urut[#urut + 1] = w[i] - w[i - 1] end
  table.sort(urut)
  local P0 = urut[math.ceil(#urut / 2)]
  if P0 < 150 then return nil end
  local k = {}
  for i = 1, n do k[i] = math.floor((w[i] - w[1]) / P0 + 0.5) end
  local function cocok(idx)
    local m = #idx
    local sk, st, skk, skt = 0, 0, 0, 0
    for _, i in ipairs(idx) do
      sk = sk + k[i]
      st = st + w[i]
      skk = skk + k[i] * k[i]
      skt = skt + k[i] * w[i]
    end
    local den = m * skk - sk * sk
    if den == 0 then return nil end
    local b = (m * skt - sk * st) / den
    local a = (st - b * sk) / m
    return a, b
  end
  local idx = {}
  for i = 1, n do idx[i] = i end
  local a, b = cocok(idx)
  if not a or b <= 0 then return nil end
  local baru = {}
  for _, i in ipairs(idx) do
    if math.abs(w[i] - (a + b * k[i])) <= 0.2 * b then baru[#baru + 1] = i end
  end
  if #baru >= 3 and #baru < #idx then
    local a2, b2 = cocok(baru)
    if a2 and b2 > 0 then
      a, b, idx = a2, b2, baru
    end
  end
  local sse = 0
  for _, i in ipairs(idx) do
    local r = w[i] - (a + b * k[i])
    sse = sse + r * r
  end
  return { bpm = 60000 / b, periode = b, k = k, idx = idx, sd = math.sqrt(sse / #idx), jumlah = #idx, total = n }
end

local function bangunLangkah(peta)
  local langkah = {}
  for _, b in ipairs(peta) do
    if b.tipe == "bertahap" then
      local jml = math.max(2, math.floor((b.akhirMs - b.mulaiMs) / 5000 + 0.5))
      for q = 0, jml - 1 do
        local f1 = q / jml
        local f2 = (q + 1) / jml
        local fm = (f1 + f2) / 2
        langkah[#langkah + 1] = {
          mulaiMs = b.mulaiMs + (b.akhirMs - b.mulaiMs) * f1,
          akhirMs = b.mulaiMs + (b.akhirMs - b.mulaiMs) * f2,
          bpm = b.bpm + (b.bpm2 - b.bpm) * fm,
          t0 = b.t0Ms,
          rantai = q > 0 }
      end
    else
      langkah[#langkah + 1] = { mulaiMs = b.mulaiMs, akhirMs = b.akhirMs, bpm = b.bpm, t0 = b.t0Ms, rantai = false }
    end
  end
  for i = 2, #langkah do
    local l, p = langkah[i], langkah[i - 1]
    if l.rantai then
      local per = 60000 / p.bpm
      local n = math.ceil((l.mulaiMs - p.t0) / per)
      l.t0 = p.t0 + n * per
    end
  end
  return langkah
end

local function cariLangkah(langkah, pos)
  local hasil = nil
  for i, l in ipairs(langkah) do
    if pos >= l.mulaiMs then hasil = i end
  end
  return hasil
end

local function jagaPeta(mine)
  if ps ~= mine or not mine.ikutPeta then return end
  if mine.lagu and mine.metOn and mine.player and mine.langkah then
    local pos = 0
    pcall(function() pos = mine.player.getCurrentPosition() end)
    local idx = cariLangkah(mine.langkah, pos)
    if idx and idx ~= mine.idxLangkah then
      mine.idxLangkah = idx
      local l = mine.langkah[idx]
      mine.tempo = l.bpm
      mine.t0 = l.t0
      MT.mulai()
      if mine.segarkan then mine.segarkan() end
    end
  end
  tunda(250, function() jagaPeta(mine) end)
end

local function kunciPrefs()
  local hasil = {}
  pcall(function()
    local it = pref().getAll().keySet().iterator()
    while it.hasNext() do hasil[#hasil + 1] = tostring(it.next()) end
  end)
  return hasil
end

local function bacaRiwayat()
  local daftar = {}
  local teks = bacaTeks("riwayat") or ""
  for baris in string.gmatch(teks, "[^\n]+") do
    local waktu, id, nama, path = string.match(baris, "^(%d+)\t([^\t]*)\t([^\t]*)\t?(.*)$")
    if waktu and id ~= "" then
      daftar[#daftar + 1] = { waktu = tonumber(waktu), id = id, nama = nama, path = path }
    end
  end
  return daftar
end

local function simpanRiwayat(daftar)
  local baris = {}
  for _, r in ipairs(daftar) do
    baris[#baris + 1] = tostring(math.floor(r.waktu)) .. "\t" .. r.id .. "\t" .. r.nama .. "\t" .. r.path
  end
  if #baris == 0 then
    hapusTeks("riwayat")
  else
    simpanTeks("riwayat", table.concat(baris, "\n"))
  end
end

local function catatRiwayat(item)
  local id = idLagu(item)
  local lain = {}
  for _, r in ipairs(bacaRiwayat()) do
    if r.id ~= id then lain[#lain + 1] = r end
  end
  lain[#lain + 1] = { waktu = os.time(), id = id, nama = item.nama, path = item.path or "" }
  simpanRiwayat(lain)
end

local function gabungRiwayat()
  local daftar = bacaRiwayat()
  local ada = {}
  for _, r in ipairs(daftar) do ada[r.id] = true end
  local diubah = false
  for _, k in ipairs(kunciPrefs()) do
    local id = string.match(k, "^off_(.+)$") or string.match(k, "^on_(.+)$") or string.match(k, "^fix_(.+)$") or string.match(k, "^peta_(.+)$")
    if id and not ada[id] then
      ada[id] = true
      local nama = string.match(id, "^(.*)_[%d%.]+$") or id
      daftar[#daftar + 1] = { waktu = 0, id = id, nama = nama, path = "" }
      diubah = true
    end
  end
  local hasil = {}
  for _, r in ipairs(daftar) do
    if bacaTeks("off_" .. r.id) or bacaTeks("on_" .. r.id) or bacaTeks("fix_" .. r.id) or bacaTeks("peta_" .. r.id) then
      hasil[#hasil + 1] = r
    else
      diubah = true
    end
  end
  if diubah then simpanRiwayat(hasil) end
  table.sort(hasil, function(a, b)
    if a.waktu ~= b.waktu then return a.waktu > b.waktu end
    return string.lower(a.nama) < string.lower(b.nama)
  end)
  return hasil
end

local function hapusHasilLagu(id)
  hapusTeks("off_" .. id)
  hapusTeks("on_" .. id)
  hapusTeks("fix_" .. id)
  hapusTeks("peta_" .. id)
  local lain = {}
  for _, r in ipairs(bacaRiwayat()) do
    if r.id ~= id then lain[#lain + 1] = r end
  end
  simpanRiwayat(lain)
  if DJL.lagu and idLagu(DJL.lagu) == id then DJL.lagu = nil end
end

local function hapusSemuaRiwayat()
  for _, k in ipairs(kunciPrefs()) do
    if string.match(k, "^off_") or string.match(k, "^on_") or string.match(k, "^fix_") or string.match(k, "^peta_") then hapusTeks(k) end
  end
  hapusTeks("riwayat")
  DJL.lagu = nil
  DJL.teksTerakhir = nil
end

local function itemDariRiwayat(r)
  local ukuran = tonumber(string.match(r.id, "_([%d%.]+)$") or "0") or 0
  local path = r.path
  local ada = false
  if path ~= "" then pcall(function() ada = File(path).exists() end) end
  if not ada then
    path = ""
    if DJL.daftar then
      for _, it in ipairs(DJL.daftar) do
        if idLagu(it) == r.id then
          path = it.path
          break
        end
      end
    end
  end
  local folder = string.match(path, "^(.*)/[^/]*$") or ""
  return { nama = r.nama, path = path, ukuran = ukuran, folder = folder, nl = string.lower(r.nama) }
end

local function ringkasHasil(r)
  local h = ambilHasil({ nama = r.nama, ukuran = tonumber(string.match(r.id, "_([%d%.]+)$") or "0") or 0 })
  local b = {}
  if h.fix then b[#b + 1] = "periksa " .. angka(h.fix, 1) end
  if h.off then b[#b + 1] = "offline " .. angka(h.off.bpm, 1) end
  if h.on then b[#b + 1] = tostring(h.on.sumber or "FreqBlog") .. " " .. angka(h.on.bpm, 1) end
  if #b == 0 then return "" end
  return ", tempo " .. table.concat(b, ", ")
end

local function namaTerakhir(path)
  return string.match(path, "([^/]+)$") or path
end

local function daftarFavorit()
  local d = {}
  for p in string.gmatch(pengaturan.favorit, "[^;]+") do d[#d + 1] = p end
  return d
end

local function adaFavorit(dir)
  for _, p in ipairs(daftarFavorit()) do
    if p == dir then return true end
  end
  return false
end

local function ubahFavorit(dir)
  local baru = {}
  local ada = false
  for _, p in ipairs(daftarFavorit()) do
    if p == dir then ada = true else baru[#baru + 1] = p end
  end
  if not ada then baru[#baru + 1] = dir end
  pengaturan.favorit = table.concat(baru, ";")
  simpanPengaturan()
  return not ada
end

local function tutupSemua()
  DJL.hentikanStudio()
  if DJL.studioNada then pcall(function() DJL.studioNada.stop() end) pcall(function() DJL.studioNada.release() end) DJL.studioNada = nil end
  MT.bersihkan()
  MT.hentikanUji()
  if DJL.akor then
    pcall(function() DJL.akor.stop() end)
    pcall(function() DJL.akor.release() end)
    DJL.akor = nil
  end
  DJL.batal = true
  DJL.batalOnline = true
  DJL.giliranPindai = (DJL.giliranPindai or 0) + 1
  local ht = DJL.ht
  local ht2 = DJL.htNet
  DJL.ht = nil
  DJL.htNet = nil
  DJL.pekerja = nil
  DJL.pekerjaNet = nil
  if ht then pcall(function() ht.quitSafely() end) end
  if ht2 then pcall(function() ht2.quitSafely() end) end
  tutupDialog()
end

local function layarCari(daftar, onPilih, kembali)
  local d = dialogBaru("Cari lagu, " .. #daftar .. " lagu")
  local etCari = E("Ketik sebagian nama lagu atau folder", "")
  local arr = ArrayList()
  local adapter = ArrayAdapter(ctx, android.R.layout.simple_list_item_1, arr)
  local lv = ListView(ctx)
  lv.setAdapter(adapter)
  local cocok = {}
  local function isi(kueri)
    arr.clear()
    cocok = {}
    local kata = {}
    for k in string.gmatch(string.lower(kueri), "%S+") do kata[#kata + 1] = k end
    for _, it in ipairs(daftar) do
      if #cocok >= 150 then break end
      local gabung = string.lower(it.nama .. " " .. it.folder)
      local semua = true
      for _, k in ipairs(kata) do
        if not string.find(gabung, k, 1, true) then
          semua = false
          break
        end
      end
      if semua then
        cocok[#cocok + 1] = it
        arr.add(it.nama .. ", " .. angka(it.ukuran / 1048576, 1) .. " MB, folder " .. namaTerakhir(it.folder))
      end
    end
    adapter.notifyDataSetChanged()
  end
  etCari.addTextChangedListener(luajava.createProxy("android.text.TextWatcher", {
    beforeTextChanged = function(s, start, count, after) end,
    onTextChanged = function(s, start, before, count) end,
    afterTextChanged = function(s) isi(tostring(s)) end }))
  lv.setOnItemClickListener(AdapterView.OnItemClickListener({
    onItemClick = aman(function(a, v, p, id)
      local it = cocok[p + 1]
      if it then onPilih(it) end
    end) }))
  local isiLayout = LinearLayout(ctx)
  isiLayout.setOrientation(1)
  isiLayout.addView(etCari)
  isiLayout.addView(lv, LinearLayout.LayoutParams(-1, -2, 1.0))
  d.setView(isiLayout)
  d.setButton("Kembali", aman(function() kembali() end))
  d.setOnCancelListener(aman(function() kembali() end))
  isi("")
  bukaDialog(d)
end

local function bukaPicker(opsi)
  local dir = opsi.pathAwal
  if not dir or dir == "" or not File(dir).exists() then dir = "/storage/emulated/0" end
  local akarList = akarPenyimpanan()
  local d = dialogBaru(opsi.judul)
  local tvPath = T(dir, 14)
  local etCari = E("Cari di folder ini", "")
  local arr = ArrayList()
  local adapter = ArrayAdapter(ctx, android.R.layout.simple_list_item_1, arr)
  local lv = ListView(ctx)
  lv.setAdapter(adapter)
  local semua, tampilan = {}, {}
  local btnFav = nil

  local function lanjut(path)
    local o = {}
    for k, v in pairs(opsi) do o[k] = v end
    o.pathAwal = path
    bukaPicker(o)
  end

  local function labelFavorit()
    if adaFavorit(dir) then return "Hapus favorit" end
    return "Tandai favorit"
  end

  local function isiDaftar(kueri)
    arr.clear()
    tampilan = {}
    local q = string.lower(kueri or "")
    for _, e in ipairs(semua) do
      if q == "" or string.find(e.nl, q, 1, true) then
        tampilan[#tampilan + 1] = e
        arr.add(e.label)
      end
    end
    adapter.notifyDataSetChanged()
  end

  local function muatDir(path, kembali)
    dir = path
    pengaturan.terakhir = path
    simpanTeks("set_terakhir", path)
    if btnFav then btnFav.setText(labelFavorit()) end
    local folders, files = {}, {}
    local tidakBisa = false
    local ok, err = pcall(function()
      local arrF = File(path).listFiles()
      if arrF == nil then
        tidakBisa = true
        return
      end
      for i = 0, panjangLarik(arrF) - 1 do
        local f = arrF[i]
        if not f.isHidden() then
          local nama = tostring(f.getName())
          local jalur = tostring(f.getAbsolutePath())
          if f.isDirectory() then
            folders[#folders + 1] = { jenis = "dir", nama = nama, path = jalur, nl = string.lower(nama), label = "Folder " .. nama }
          else
            local ukuran = f.length()
            if opsi.filter(nama, ukuran) then
              files[#files + 1] = { jenis = "file", nama = nama, path = jalur, ukuran = ukuran, folder = path, nl = string.lower(nama), label = nama .. ", " .. angka(ukuran / 1048576, 1) .. " MB" }
            end
          end
        end
      end
    end)
    table.sort(folders, function(a, b) return a.nl < b.nl end)
    table.sort(files, function(a, b) return a.nl < b.nl end)
    semua = {}
    for _, e in ipairs(folders) do semua[#semua + 1] = e end
    for _, e in ipairs(files) do semua[#semua + 1] = e end
    if tidakBisa then
      tvPath.setText(path .. ", tidak bisa dibaca. Periksa izin penyimpanan untuk Jieshuo.")
    else
      tvPath.setText(path .. ", " .. #folders .. " folder, " .. #files .. " berkas")
    end
    etCari.setText("")
    isiDaftar("")
    DJL.gulir = DJL.gulir or {}
    local posisi = nil
    if kembali then posisi = DJL.gulir[path] end
    DJL.gulir[path] = nil
    pcall(function() lv.setSelection(0) end)
    if posisi and posisi > 0 then
      pcall(function() lv.setSelection(posisi) end)
    end
    tunda(200, function()
      local anak = lv.getChildAt(0)
      if anak then anak.requestFocus() else lv.requestFocus() end
    end)
    if tidakBisa then toast("Folder tidak bisa dibaca. Periksa izin penyimpanan untuk Jieshuo.") end
    if not ok then
      local atas = string.match(path, "^(.*)/[^/]+$")
      tampilGalat("Folder tidak bisa dibaca", path .. "\n" .. tostring(err), function()
        if atas and atas ~= "" and atas ~= path then lanjut(atas) else opsi.onBatal() end
      end)
    end
  end

  local function keLokasi()
    local butir, jalur = {}, {}
    for _, r in ipairs(akarList) do
      if r == "/storage/emulated/0" then
        butir[#butir + 1] = "Penyimpanan internal"
      else
        butir[#butir + 1] = "Penyimpanan eksternal " .. namaTerakhir(r)
      end
      jalur[#jalur + 1] = r
    end
    if pengaturan.terakhir ~= "" then
      butir[#butir + 1] = "Folder terakhir: " .. namaTerakhir(pengaturan.terakhir)
      jalur[#jalur + 1] = pengaturan.terakhir
    end
    for _, f in ipairs(daftarFavorit()) do
      butir[#butir + 1] = "Favorit: " .. namaTerakhir(f)
      jalur[#jalur + 1] = f
    end
    layarDaftar({
      judul = "Pilih lokasi",
      butir = butir,
      pilih = function(i) lanjut(jalur[i]) end,
      kembali = function() lanjut(dir) end })
  end

  etCari.addTextChangedListener(luajava.createProxy("android.text.TextWatcher", {
    beforeTextChanged = function(s, start, count, after) end,
    onTextChanged = function(s, start, before, count) end,
    afterTextChanged = function(s) isiDaftar(tostring(s)) end }))
  lv.setOnItemClickListener(AdapterView.OnItemClickListener({
    onItemClick = aman(function(a, v, p, id)
      local e = tampilan[p + 1]
      if not e then return end
      if e.jenis == "dir" then
        if tostring(etCari.getText()) == "" then
          DJL.gulir = DJL.gulir or {}
          DJL.gulir[dir] = lv.getFirstVisiblePosition()
        end
        muatDir(e.path)
      else
        opsi.onPilih(e)
      end
    end) }))

  local baris = LinearLayout(ctx)
  baris.setOrientation(0)
  baris.addView(B("Lokasi", function() keLokasi() end), LinearLayout.LayoutParams(0, -2, 1.0))
  btnFav = B(labelFavorit(), function()
    local jadi = ubahFavorit(dir)
    btnFav.setText(labelFavorit())
    if jadi then toast("Folder ditandai favorit") else toast("Dihapus dari favorit") end
  end)
  baris.addView(btnFav, LinearLayout.LayoutParams(0, -2, 1.0))
  if opsi.cariSemua then
    baris.addView(B("Cari semua", function()
      muatDaftarLagu(false, function(daftar)
        if #daftar == 0 then
          toast("Tidak ada lagu ditemukan. Periksa izin audio Jieshuo.")
          return
        end
        layarCari(daftar, function(it) opsi.onPilih(it) end, function() lanjut(dir) end)
      end)
    end), LinearLayout.LayoutParams(0, -2, 1.0))
  end

  local isiLayout = LinearLayout(ctx)
  isiLayout.setOrientation(1)
  isiLayout.setPadding(dp(8), dp(4), dp(8), dp(4))
  isiLayout.addView(tvPath)
  isiLayout.addView(etCari)
  isiLayout.addView(lv, LinearLayout.LayoutParams(-1, -2, 1.0))
  isiLayout.addView(baris)
  d.setView(isiLayout)
  d.setButton("Batal", function() opsi.onBatal() end)
  d.setOnCancelListener(function() opsi.onBatal() end)
  d.setOnKeyListener(function(dialog, keyCode, event)
    if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
      local atas = string.match(dir, "^(.*)/[^/]+$")
      local diAkar = (atas == nil or atas == "")
      for _, a in ipairs(akarList) do
        if dir == a then diAkar = true end
      end
      if diAkar then
        opsi.onBatal()
      else
        muatDir(atas, true)
      end
      return true
    end
    return false
  end)
  bukaDialog(d)
  muatDir(dir)
end

local function layarTempo(cfg)
  local tvInfo = T("", 16)
  local slBulat, slHalus
  local awal = cfg.ambil()
  if awal < 30 then awal = 30 elseif awal > 300 then awal = 300 end
  local bulatAwal = math.floor(awal)
  local halusAwal = math.floor((awal - bulatAwal) * 10 + 0.5)
  if halusAwal >= 10 then
    bulatAwal = bulatAwal + 1
    halusAwal = 0
  end
  local etAngka = E("Isi tempo dalam BPM", string.format("%.1f", bulatAwal + halusAwal / 10), true)
  local function nilaiSekarang()
    return slBulat.ambil() + slHalus.ambil() / 10
  end
  local function segarkanInfo(v)
    if cfg.info then
      tvInfo.setText(cfg.info(v))
    else
      tvInfo.setText("Tempo " .. angka(v, 1) .. " BPM")
    end
  end
  local function setelKe(v, terapkan)
    if v < 30 then v = 30 elseif v > 300 then v = 300 end
    local bulat = math.floor(v)
    local halus = math.floor((v - bulat) * 10 + 0.5)
    if halus >= 10 then
      bulat = bulat + 1
      halus = 0
    end
    slBulat.setNilai(bulat)
    slHalus.setNilai(halus)
    local total = bulat + halus / 10
    etAngka.setText(string.format("%.1f", total))
    segarkanInfo(total)
    if terapkan then cfg.setel(total) end
  end
  local function saatGeser()
    local v = nilaiSekarang()
    segarkanInfo(v)
    etAngka.setText(string.format("%.1f", v))
    tundaKunci("tempo", 350, function() cfg.setel(nilaiSekarang()) end)
  end
  slBulat = buatSlider({
    min = 30, max = 300, langkah = 1, nilai = bulatAwal,
    label = function(v) return "Tempo bulat: " .. tostring(v) .. " BPM" end,
    saatUbah = function(v) saatGeser() end })
  slHalus = buatSlider({
    min = 0, max = 9, langkah = 1, nilai = halusAwal,
    label = function(v) return "Penyetelan halus: tambah " .. angka(v / 10, 1) .. " BPM" end,
    saatUbah = function(v) saatGeser() end })
  segarkanInfo(bulatAwal + halusAwal / 10)
  local tombol = {}
  tombol[#tombol + 1] = B("Terapkan angka", function()
    local t = string.gsub(pangkas(tostring(etAngka.getText())), ",", ".")
    local v = tonumber(t)
    if not v or v < 30 or v > 300 then
      toast("Tempo harus antara 30 dan 300")
    else
      setelKe(v, true)
    end
  end)
  tombol[#tombol + 1] = B("Dua kali lipat", function() setelKe(nilaiSekarang() * 2, true) end)
  tombol[#tombol + 1] = B("Setengahnya", function() setelKe(nilaiSekarang() / 2, true) end)
  for _, tb in ipairs(cfg.tambahan or {}) do
    tombol[#tombol + 1] = B(tb[1], function()
      tb[2]()
      setelKe(cfg.ambil(), false)
    end)
  end
  tombol[#tombol + 1] = B("Kembali", function() cfg.kembali() end)
  local d = layarForm("Atur tempo", cfg.kembali, tvInfo, etAngka, tombol[1], slBulat.view, slHalus.view, tombol[2], tombol[3], tombol[4], tombol[5], tombol[6])
  return d
end

local function layarKetuk(cfg)
  local k = cfg.ketuk
  local tv = T("", 16)
  local function info()
    if k.hasil then
      tv.setText("Ketukan: " .. angka(k.hasil.bpm, 1) .. " BPM dari " .. tostring(k.hasil.jumlah) .. " ketukan, simpangan " .. tostring(math.floor(k.hasil.sd)) .. " ms.")
    else
      tv.setText("Ketukan tercatat: " .. tostring(#k.t) .. ". Ketuk minimal tiga kali mengikuti ketukan lagu.")
    end
  end
  info()
  layarForm(cfg.judul or "Ketuk tempo", cfg.kembali, tv,
    B("Ketuk", function()
      if cfg.butuhLagu and not (ps and ps.player and ps.lagu) then
        toast("Putar lagunya dulu, lalu ketuk mengikuti ketukan")
        return
      end
      local t = System.currentTimeMillis()
      local pos = 0
      if cfg.butuhLagu then pcall(function() pos = ps.player.getCurrentPosition() end) end
      if #k.t > 0 and t - k.t[#k.t] > 2500 then
        k.t = {}
        k.pos = {}
        k.hasil = nil
      end
      k.t[#k.t + 1] = t
      k.pos[#k.pos + 1] = pos
      if #k.t > 32 then
        table.remove(k.t, 1)
        table.remove(k.pos, 1)
      end
      local r = hitungKetukan(k.t)
      if r then
        k.hasil = r
        toast(angka(r.bpm, 1))
      else
        toast(tostring(#k.t))
      end
      info()
    end),
    B("Pakai hasil ketukan", function()
      if not k.hasil then
        toast("Belum ada hasil ketukan, ketuk minimal tiga kali")
        return
      end
      cfg.saatPakai(k.hasil, k)
    end),
    B("Ulangi ketukan", function()
      k.t = {}
      k.pos = {}
      k.hasil = nil
      info()
      toast("Ketukan diulang")
    end),
    B("Kembali", function() cfg.kembali() end))
end

local function ambilKandidatAkor(item)
  local h = ambilHasil(item)
  local daftar, nama = {}, {}
  if h.off then
    daftar[#daftar + 1] = { h.off.pc1, h.off.mode1 }
    nama[#nama + 1] = "Offline pilihan pertama: " .. namaKunci(h.off.pc1, h.off.mode1)
    daftar[#daftar + 1] = { h.off.pc2, h.off.mode2 }
    nama[#nama + 1] = "Offline pilihan kedua: " .. namaKunci(h.off.pc2, h.off.mode2)
  end
  if h.on then
    local pc, md = uraiKunci(h.on.kunci)
    if pc then
      daftar[#daftar + 1] = { pc, md }
      nama[#nama + 1] = tostring(h.on.sumber or "FreqBlog") .. ": " .. namaKunci(pc, md)
    end
  end
  return daftar, nama
end

local function menuAkor(item, kembali)
  local daftar, nama = ambilKandidatAkor(item)
  if #daftar == 0 then
    toast("Belum ada kunci untuk dimainkan.")
    kembali()
    return
  end
  layarDaftar({
    judul = "Dengarkan akor kunci",
    butir = nama,
    pilih = function(i)
      MT.akor(daftar[i][1], daftar[i][2])
      toast("Memainkan akor " .. namaKunci(daftar[i][1], daftar[i][2]))
    end,
    kembali = kembali })
end

tampilHasilAnalisis = function(item)
  DJL.sibuk = false
  local h = ambilHasil(item)
  if h.off or h.on or h.peta or h.fix then catatRiwayat(item) end
  local teks = teksRingkasHasil(item)
  DJL.catatan = nil
  dialogPesan("Hasil analisis", teks, {
    { "Tutup", function() menuLagu(item) end },
    { "Pemutar lagu dan metronom", function() layarPemutar(item) end },
    { "Menu hasil", function() menuHasil(item) end } }, function() menuLagu(item) end)
end

local function jalankanAnalisis(item, mode, paksa)
  DJL.lagu = item
  DJL.catatan = nil
  if item.path == nil or item.path == "" then
    toast("Berkas lagu tidak ditemukan. Pilih lagunya lewat Pilih lagu.")
    menuLagu(item)
    return
  end
  local id = idLagu(item)
  local penyedia = pengaturan.penyedia
  local nama = namaSingkat(penyedia)
  if paksa then
    hapusTeks("off_" .. id)
    hapusTeks("on_" .. id)
    hapusTeks("peta_" .. id)
  end
  local denganPeta = (mode == "peta")
  local dataOff = bacaTeks("off_" .. id)
  local perluChord = not dataOff or not string.find(dataOff, "chordv=3", 1, true)
  local perluOff = (mode == "off" or mode == "dua") and (not dataOff or perluChord)
  if denganPeta then perluOff = not bacaTeks("peta_" .. id) or perluChord end
  local dataOn = bacaTeks("on_" .. id)
  local sumberLama = nil
  if dataOn then sumberLama = string.match(dataOn, "sumber=([^\n]*)") or "FreqBlog" end
  local perluOn = (mode == "on" or mode == "dua") and (not dataOn or sumberLama ~= nama)
  if perluOn and kunciKosong(penyedia) then
    if mode == "on" then
      dialogPesan("Kunci " .. nama .. " belum diisi",
        "Analisis online lewat FreqBlog butuh kunci gratis. Kuota gratisnya 25 analisis per bulan. Pilih Dapatkan kunci untuk membuka halamannya, lalu Pengaturan untuk mengisinya.", {
        { "Tutup", function() menuAnalisis(item) end },
        { "Dapatkan kunci", function()
          bukaTautan(LAMAN_KUNCI)
          menuAnalisis(item)
        end },
        { "Pengaturan", function() layarPenyedia(function() menuAnalisis(item) end) end } }, function() menuAnalisis(item) end)
      return
    end
    perluOn = false
    DJL.catatan = "Analisis online dilewati karena kunci " .. nama .. " belum diisi."
  end

  local function langkahOnline()
    if not perluOn then
      tampilHasilAnalisis(item)
      return
    end
    local giliran = (DJL.idUnggah or 0) + 1
    DJL.idUnggah = giliran
    DJL.batalOnline = false
    tampilProgres("Mengunggah ke " .. nama, "Menyiapkan unggahan", function()
      batalkanUnggah()
      DJL.sibuk = false
      menuAnalisis(item)
    end)
    jalankanBertahap(function()
      return kirimOnline(penyedia, item.path, perbaruiProgres)
    end, function(ok, hasil)
      if DJL.idUnggah ~= giliran then return end
      if DJL.batalOnline then return end
      if not ok then hasil = { galat = "Tidak bisa menghubungi " .. nama .. ". " .. tostring(hasil) } end
      if hasil.galat then
        DJL.catatan = "Online gagal: " .. hasil.galat
      else
        simpanTeks("on_" .. id, serial(hasil))
      end
      tampilHasilAnalisis(item)
    end, "jaringan")
  end

  if not perluOff then
    langkahOnline()
    return
  end

  local function mulaiOffline()
    DJL.batal = false
    DJL.analisisJalan = true
    DJL.sibuk = true
    DJL.umumPersen = 25
    local status = {}
    tampilProgres("Menganalisis offline", "Menganalisis offline, 0 persen", function()
      DJL.batal = true
      DJL.sibuk = false
      menuAnalisis(item)
    end)
    jalankanBertahap(function()
      return analisisOffline(item, lapor, denganPeta, status)
    end, function(ok, hasil, pesan, peta)
      DJL.analisisJalan = false
      bersihkanSD()
      if DJL.batal then
        DJL.sibuk = false
        return
      end
      if not ok then
        if status.hasil then
          simpanTeks("off_" .. id, serial(status.hasil))
          DJL.catatan = "Peta tempo gagal: " .. tostring(hasil)
        else
          DJL.catatan = "Offline gagal: " .. tostring(hasil)
        end
      elseif not hasil then
        DJL.catatan = "Offline gagal: " .. tostring(pesan)
      else
        simpanTeks("off_" .. id, serial(hasil))
        if peta then simpanPeta(id, peta) end
      end
      local w = status.waktu
      if w then
        local ket = "Waktu proses offline: dekode " .. angka(w.dekode / 1000, 1) .. " detik, nada " .. angka(w.nada / 1000, 1) .. " detik, tempo " .. angka(w.tempo / 1000, 1) .. " detik"
        if w.peta > 0 then ket = ket .. ", peta " .. angka(w.peta / 1000, 1) .. " detik" end
        DJL.catatan = (DJL.catatan and (DJL.catatan .. "\n") or "") .. ket .. "."
      end
      langkahOnline()
    end)
  end

  local function tunggu()
    if DJL.analisisJalan then
      tunda(150, tunggu)
    else
      mulaiOffline()
    end
  end
  tunggu()
end

menuAnalisis = function(item)
  DJL.lagu = item
  local h = ambilHasil(item)
  local butir, aksi = {}, {}
  if h.off or h.on or h.peta then
    butir[#butir + 1] = "Lihat hasil tersimpan"
    aksi[#aksi + 1] = function() tampilHasilAnalisis(item) end
  end
  butir[#butir + 1] = "Analisis offline, gratis tanpa internet"
  aksi[#aksi + 1] = function() jalankanAnalisis(item, "off", false) end
  butir[#butir + 1] = "Analisis online lewat " .. teksOnline(pengaturan.penyedia)
  aksi[#aksi + 1] = function() jalankanAnalisis(item, "on", false) end
  butir[#butir + 1] = "Offline dan online sekaligus"
  aksi[#aksi + 1] = function() jalankanAnalisis(item, "dua", false) end
  butir[#butir + 1] = "Offline lengkap dengan peta tempo, lebih lama"
  aksi[#aksi + 1] = function() jalankanAnalisis(item, "peta", false) end
  layarDaftar({
    judul = "Analisis: " .. item.nama,
    butir = butir,
    pilih = function(i) aksi[i]() end,
    kembali = function() menuLagu(item) end })
end

local function teksTempoHasil(item)
  local h = ambilHasil(item)
  local b = { "Lagu: " .. item.nama }
  if h.off then b[#b + 1] = "Tempo offline: " .. angka(h.off.bpm, 1) .. " BPM. Keyakinan tempo: " .. yakinTempoOffline(h.off) .. "." end
  if h.on and tonumber(h.on.bpm) and h.on.bpm > 0 then b[#b + 1] = "Tempo " .. tostring(h.on.sumber or "online") .. ": " .. angka(h.on.bpm, 1) .. " BPM." end
  if h.fix then b[#b + 1] = "Tempo yang sudah diperiksa: " .. angka(h.fix, 1) .. " BPM." end
  if h.peta then b[#b + 1] = teksPeta(h.peta, ambilTranspose(item)) end
  if not h.off and not h.on and not h.fix and not h.peta then b[#b + 1] = "Belum ada hasil tempo." end
  return table.concat(b, "\n")
end

local function teksNadaHasil(item)
  local h = ambilHasil(item)
  local geser = ambilTranspose(item)
  local b = { "Lagu: " .. item.nama }
  if geser ~= 0 then b[#b + 1] = "Tampilan transpose: " .. tostring(geser) .. " semiton. Audio dan pitch tetap asli." end
  if h.off then
    b[#b + 1] = "Nada dasar offline: " .. namaKunciGeser(h.off.pc1, h.off.mode1, geser) .. "."
    b[#b + 1] = "Kemungkinan kedua: " .. namaKunciGeser(h.off.pc2, h.off.mode2, geser) .. "."
    b[#b + 1] = "Keyakinan relatif: " .. yakinKunciOffline(h.off.skor1, h.off.skor2) .. "."
  end
  if h.on then
    local pc, md = uraiKunci(h.on.kunci)
    if pc then b[#b + 1] = "Nada dasar " .. tostring(h.on.sumber or "online") .. ": " .. namaKunciGeser(pc, md, geser) .. "."
    else b[#b + 1] = "Nada dasar " .. tostring(h.on.sumber or "online") .. ": " .. tostring(h.on.kunci) .. "." end
  end
  if h.peta then
    for i, p in ipairs(h.peta) do
      if p.pc ~= nil then b[#b + 1] = "Nada dasar bagian peta tempo " .. i .. ": " .. namaKunciGeser(p.pc, p.mode, geser) .. ", " .. waktuTeks(p.mulaiMs) .. "." end
    end
  end
  if not h.off and not h.on and not h.peta then b[#b + 1] = "Belum ada hasil nada dasar." end
  return table.concat(b, "\n")
end

local function teksModulasiHasil(item)
  local h = ambilHasil(item)
  local geser = ambilTranspose(item)
  if not h.peta or #h.peta == 0 then
    return "Peta tempo dengan analisis nada per bagian belum tersedia. Jalankan analisis offline lengkap dengan peta tempo."
  end
  local bagian = {}
  for i, p in ipairs(h.peta) do
    if p.pc ~= nil then
      bagian[#bagian + 1] = { pc = p.pc, mode = p.mode or 0, mulai = p.mulaiMs or 0, skor = p.skor or 0, nomor = i }
    end
  end
  if #bagian == 0 then return "Nada per bagian belum cukup terdeteksi untuk membaca modulasi." end
  local teks = { "Analisis modulasi mayor/minor untuk lagu: " .. item.nama }
  if geser ~= 0 then teks[#teks + 1] = "Tampilan nada digeser " .. tostring(geser) .. " semiton; audio tetap asli." end
  teks[#teks + 1] = ""
  teks[#teks + 1] = "Nada dasar tiap bagian:"
  for _, b in ipairs(bagian) do
    teks[#teks + 1] = "Bagian " .. b.nomor .. ", " .. waktuTeks(b.mulai) .. ": " .. namaKunciGeser(b.pc, b.mode, geser) .. "."
  end
  local perubahan = 0
  teks[#teks + 1] = ""
  teks[#teks + 1] = "Perubahan nada dasar:"
  for i = 2, #bagian do
    local a, b = bagian[i - 1], bagian[i]
    if a.pc ~= b.pc or a.mode ~= b.mode then
      perubahan = perubahan + 1
      local berulang = bagian[i + 1] and bagian[i + 1].pc == b.pc and bagian[i + 1].mode == b.mode
      local status = berulang and "indikasi lebih kuat karena berlanjut pada bagian berikutnya" or "indikasi perubahan; perlu pemeriksaan pendengaran"
      teks[#teks + 1] = "Modulasi " .. perubahan .. ": " .. namaKunciGeser(a.pc, a.mode, geser) .. " ke " .. namaKunciGeser(b.pc, b.mode, geser) .. ", mulai " .. waktuTeks(b.mulai) .. "; " .. status .. "."
    end
  end
  if perubahan == 0 then teks[#teks + 1] = "Belum ditemukan perubahan nada dasar yang konsisten pada peta ini." end
  teks[#teks + 1] = "Catatan: hasil modulasi merupakan indikasi analisis per bagian, bukan kepastian mutlak."
  return table.concat(teks, "\n")
end

local function teksChordHasil(item)
  local h = ambilHasil(item)
  local geser = ambilTranspose(item)
  local daftar = h.off and h.off.chord or {}
  if not daftar or #daftar == 0 then return "Belum ada rangkaian chord offline. Jalankan analisis offline terlebih dahulu." end
  local teks = { "Lagu: " .. item.nama, "Jumlah perubahan chord: " .. tostring(#daftar) }
  if geser ~= 0 then teks[#teks + 1] = "Transpose tampilan: " .. tostring(geser) .. " semiton. Audio tetap asli." end
  teks[#teks + 1] = ""
  for i, c in ipairs(daftar) do
    if i <= 150 then
      teks[#teks + 1] = "Chord " .. i .. ": " .. geserNamaChord(c.nama, geser)
      teks[#teks + 1] = "Waktu: " .. waktuTeks(c.mulai * 1000) .. " sampai " .. waktuTeks(c.akhir * 1000)
      if c.kualitas and c.kualitas ~= "" then teks[#teks + 1] = "Jenis: " .. c.kualitas
      else teks[#teks + 1] = "Jenis: belum tersedia pada hasil analisis lama" end
      if c.nada and c.nada ~= "" then teks[#teks + 1] = "Nada penyusun: " .. geserNamaNada(c.nada, geser)
      else teks[#teks + 1] = "Nada penyusun: belum tersedia pada hasil analisis lama" end
      if c.bass and c.bass ~= "" then teks[#teks + 1] = "Nada bass: " .. geserNamaNada(c.bass, geser) end
      teks[#teks + 1] = "Skor kecocokan pola: " .. angka((c.skor or 0) * 100, 1) .. "%"
      teks[#teks + 1] = ""
    end
  end
  if #daftar > 150 then teks[#teks + 1] = "Hanya 150 perubahan chord pertama yang ditampilkan." end
  return table.concat(teks, "\n")
end

menuHasil = function(item)
  local butir, aksi = {}, {}
  butir[#butir + 1] = "Baca ringkasan hasil"
  aksi[#aksi + 1] = function()
    dialogPesan("Ringkasan hasil", teksRingkasHasil(item), { { "Kembali", function() menuHasil(item) end } }, function() menuHasil(item) end)
  end
  butir[#butir + 1] = "Lihat hasil tempo"
  aksi[#aksi + 1] = function()
    dialogPesan("Hasil tempo", teksTempoHasil(item), { { "Kembali", function() menuHasil(item) end } }, function() menuHasil(item) end)
  end
  butir[#butir + 1] = "Lihat nada dasar"
  aksi[#aksi + 1] = function()
    dialogPesan("Hasil nada dasar", teksNadaHasil(item), { { "Kembali", function() menuHasil(item) end } }, function() menuHasil(item) end)
  end
  butir[#butir + 1] = "Lihat modulasi mayor/minor"
  aksi[#aksi + 1] = function()
    dialogPesan("Modulasi mayor/minor", teksModulasiHasil(item), { { "Kembali", function() menuHasil(item) end } }, function() menuHasil(item) end)
  end
  butir[#butir + 1] = "Lihat hasil chord offline"
  aksi[#aksi + 1] = function()
    dialogPesan("Hasil chord offline", teksChordHasil(item), { { "Kembali", function() menuHasil(item) end } }, function() menuHasil(item) end)
  end
  butir[#butir + 1] = "Salin ringkasan hasil"
  aksi[#aksi + 1] = function() salin(teksRingkasHasil(item)) end
  butir[#butir + 1] = "Salin hasil tempo"
  aksi[#aksi + 1] = function() salin(teksTempoHasil(item)) end
  butir[#butir + 1] = "Salin nada dasar"
  aksi[#aksi + 1] = function() salin(teksNadaHasil(item)) end
  butir[#butir + 1] = "Salin hasil chord offline"
  aksi[#aksi + 1] = function() salin(teksChordHasil(item)) end
  butir[#butir + 1] = "Salin seluruh hasil analisis"
  aksi[#aksi + 1] = function() salin(susunTeks(item) .. "\n\n" .. teksModulasiHasil(item) .. "\n\n" .. teksChordHasil(item)) end
  butir[#butir + 1] = "Transpose tampilan nada"
  aksi[#aksi + 1] = function() menuTranspose(item, function() menuHasil(item) end) end
  butir[#butir + 1] = "Dengarkan akor kunci"
  aksi[#aksi + 1] = function() menuAkor(item, function() menuHasil(item) end) end
  butir[#butir + 1] = "Hitung ulang semuanya"
  aksi[#aksi + 1] = function() jalankanAnalisis(item, "dua", true) end
  layarDaftar({
    judul = "Hasil: " .. item.nama,
    butir = butir,
    pilih = function(i) aksi[i]() end,
    kembali = function() menuLagu(item) end })
end

local function menuManual(item)
  local h0 = ambilHasil(item)
  local nilai = 0
  if h0.fix then nilai = h0.fix end
  local ketuk = { t = {}, pos = {} }
  local utama
  local function atur()
    layarTempo({
      ambil = function()
        if nilai > 0 then return nilai end
        return 120
      end,
      setel = function(v) nilai = v end,
      kembali = function() utama() end })
  end
  utama = function()
    local teksAtas = "Belum ada angka. Atur tempo atau ketuk mengikuti ketukan lagu."
    if nilai > 0 then
      teksAtas = "Tempo saat ini " .. angka(nilai, 1) .. " BPM. Belum disimpan kalau baru diubah."
    end
    local butir, aksi = {}, {}
    butir[#butir + 1] = "Atur tempo"
    aksi[#aksi + 1] = function() atur() end
    butir[#butir + 1] = "Ketuk mengikuti ketukan lagu"
    aksi[#aksi + 1] = function()
      layarKetuk({
        judul = "Ketuk tempo",
        ketuk = ketuk,
        butuhLagu = false,
        saatPakai = function(r)
          nilai = r.bpm
          toast("Tempo " .. angka(nilai, 1))
          utama()
        end,
        kembali = function() utama() end })
    end
    butir[#butir + 1] = "Dengarkan metronom dengan angka ini"
    aksi[#aksi + 1] = function()
      if nilai > 0 then MT.ujiTempo(nilai) else toast("Belum ada angka") end
    end
    butir[#butir + 1] = "Simpan sebagai hasil"
    aksi[#aksi + 1] = function()
      if nilai > 0 then
        simpanTeks("fix_" .. idLagu(item), tostring(nilai))
        catatRiwayat(item)
        toast("Tersimpan: " .. angka(nilai, 1) .. " BPM")
        menuLagu(item)
      else
        toast("Belum ada hasil untuk disimpan")
      end
    end
    butir[#butir + 1] = "Tutup tanpa menyimpan"
    aksi[#aksi + 1] = function() menuLagu(item) end
    layarDaftar({
      judul = "Analisis manual",
      atas = T(teksAtas, 15),
      butir = butir,
      pilih = function(i) aksi[i]() end,
      kembali = function() menuLagu(item) end })
  end
  utama()
end

menuLagu = function(item)
  DJL.lagu = item
  local butir, aksi = {}, {}
  butir[#butir + 1] = "Analisis"
  aksi[#aksi + 1] = function() menuAnalisis(item) end
  butir[#butir + 1] = "Hasil"
  aksi[#aksi + 1] = function() menuHasil(item) end
  butir[#butir + 1] = "Pemutar lagu dan metronom"
  aksi[#aksi + 1] = function() layarPemutar(item) end
  butir[#butir + 1] = "Analisis manual"
  aksi[#aksi + 1] = function() menuManual(item) end
  butir[#butir + 1] = "Pilih lagu lain"
  aksi[#aksi + 1] = function() pilihLagu() end
  layarDaftar({
    judul = item.nama,
    butir = butir,
    pilih = function(i) aksi[i]() end,
    kembali = function() menuUtama() end })
end

pilihLagu = function()
  bukaPicker({
    judul = "Pilih lagu",
    pathAwal = pengaturan.terakhir,
    cariSemua = true,
    filter = function(nama, ukuran)
      local ekst = string.lower(string.match(nama, "%.(%w+)$") or "")
      return EKSTENSI[ekst] == true
    end,
    onPilih = function(e)
      menuLagu({ nama = e.nama, path = e.path, ukuran = e.ukuran, folder = e.folder or "", nl = string.lower(e.nama) })
    end,
    onBatal = function() menuUtama() end })
end

local function menuRiwayatItem(e)
  local function perluBerkas(fn)
    local it = itemDariRiwayat(e)
    if it.path ~= "" then
      fn(it)
      return
    end
    muatDaftarLagu(false, function()
      fn(itemDariRiwayat(e))
    end)
  end
  layarDaftar({
    judul = e.nama,
    butir = { "Lihat hasil", "Analisis atau putar lagu ini", "Hapus dari riwayat" },
    pilih = function(j)
      if j == 1 then
        tampilHasilAnalisis(itemDariRiwayat(e))
      elseif j == 2 then
        perluBerkas(function(it) menuLagu(it) end)
      else
        dialogPesan("Hapus riwayat", "Hapus riwayat dan hasil tersimpan untuk lagu ini?\n" .. e.nama, {
          { "Hapus", function()
            hapusHasilLagu(e.id)
            toast("Riwayat dihapus")
            menuRiwayat()
          end },
          { "Batal", function() menuRiwayatItem(e) end } }, function() menuRiwayatItem(e) end)
      end
    end,
    kembali = function() menuRiwayat() end })
end

menuRiwayat = function()
  local r = gabungRiwayat()
  if #r == 0 then
    layarDaftar({
      judul = "Riwayat lagu kosong, belum ada lagu yang dianalisis",
      butir = {},
      pilih = function() end,
      kembali = function() menuUtama() end })
    return
  end
  local label = {}
  for i, e in ipairs(r) do label[i] = e.nama .. ringkasHasil(e) end
  label[#label + 1] = "Hapus semua riwayat"
  layarDaftar({
    judul = "Riwayat lagu, " .. #r .. " lagu",
    butir = label,
    pilih = function(i)
      if i == #label then
        dialogPesan("Hapus semua riwayat", "Hapus seluruh riwayat dan semua hasil analisis yang tersimpan? Tindakan ini tidak bisa dibatalkan.", {
          { "Hapus semua", function()
            hapusSemuaRiwayat()
            toast("Seluruh riwayat dihapus")
            menuRiwayat()
          end },
          { "Batal", function() menuRiwayat() end } }, function() menuRiwayat() end)
        return
      end
      menuRiwayatItem(r[i])
    end,
    kembali = function() menuUtama() end })
end

DJL.studio = DJL.studio or {}
DJL.studio.nada = { C = 0, ["C#"] = 1, Db = 1, D = 2, ["D#"] = 3, Eb = 3, E = 4, F = 5, ["F#"] = 6, Gb = 6, G = 7, ["G#"] = 8, Ab = 8, A = 9, ["A#"] = 10, Bb = 10, B = 11 }
DJL.studio.pola = { "balok", "arpeggio", "bass", "pop" }
DJL.studio.namaPola = { balok = "Balok chord", arpeggio = "Arpeggio", bass = "Bass dan chord", pop = "Iringan ritmis pop" }
DJL.studio.track = nil
DJL.studio.jalan = false

function DJL.studio.parseChord(teks)
  local t = pangkas(teks)
  t = string.gsub(t, "^%s+", "")
  local akar = string.match(t, "^([A-Ga-g][#b]?)")
  if not akar then return nil end
  akar = string.upper(string.sub(akar, 1, 1)) .. string.sub(akar, 2)
  local pc = DJL.studio.nada[akar]
  if pc == nil then return nil end
  local sisa = string.sub(t, #string.match(t, "^([A-Ga-g][#b]?)") + 1)
  local minor = string.find(string.lower(sisa), "^m") ~= nil and string.find(string.lower(sisa), "^maj") == nil
  local diminished = string.find(string.lower(sisa), "^dim") ~= nil or string.find(sisa, "°", 1, true) ~= nil
  local augmented = string.find(string.lower(sisa), "^aug") ~= nil or string.find(sisa, "%+") ~= nil
  local third = minor and 3 or 4
  local fifth = 7
  if diminished then third, fifth = 3, 6 elseif augmented then fifth = 8 end
  return { nama = t, pc = pc, nada = { pc, (pc + third) % 12, (pc + fifth) % 12 } }
end

function DJL.studio.daftarChord(teks)
  local hasil, gagal = {}, {}
  for token in string.gmatch(tostring(teks or ""), "[^,%s;]+") do
    local c = DJL.studio.parseChord(token)
    if c then hasil[#hasil + 1] = c else gagal[#gagal + 1] = token end
  end
  return hasil, gagal
end

DJL.hentikanStudio = function()
  DJL.studio.jalan = false
  if DJL.studio.track then
    pcall(function() DJL.studio.track.pause() end)
    pcall(function() DJL.studio.track.flush() end)
    pcall(function() DJL.studio.track.stop() end)
    pcall(function() DJL.studio.track.release() end)
    DJL.studio.track = nil
  end
end

function DJL.studio.bangunAudio(daftar, bpm, pola, ketukPerChord)
  local laju = LAJU_AKOR
  local ketuk = 60 / bpm
  ketukPerChord = math.max(1, math.min(16, tonumber(ketukPerChord) or 4))
  local durasi = #daftar * ketuk * ketukPerChord
  if durasi > 180 then error("Progresi terlalu panjang. Maksimal tiga menit per pemutaran.") end
  local total = math.max(1, math.floor(durasi * laju))
  local buffer = larik("Short", total)
  local nadaPer = ketuk * laju
  local function tambahNada(sum, freq, t, env)
    local fase = 2 * math.pi * freq * t / laju
    return sum + (math.sin(fase) + 0.18 * math.sin(fase * 2) + 0.06 * math.sin(fase * 3)) * env
  end
  for idx, chord in ipairs(daftar) do
    local awal = math.floor((idx - 1) * ketuk * ketukPerChord * laju)
    local akhir = math.min(total, math.floor(idx * ketuk * ketukPerChord * laju))
    local frek = {}
    for _, n in ipairs(chord.nada) do frek[#frek + 1] = 130.813 * 2 ^ ((n + 12) / 12) end
    local bass = 65.406 * 2 ^ ((chord.pc + 12) / 12)
    for i = awal, akhir - 1 do
      local lokal = i - awal
      local beat = math.floor(lokal / nadaPer)
      local dalam = lokal - beat * nadaPer
      local sum, env = 0, 0
      if pola == "balok" then
        local t = lokal / laju
        env = math.min(1, t * 18, math.max(0.08, (durasi / #daftar - t) * 8))
        for _, f in ipairs(frek) do sum = tambahNada(sum, f, lokal, env * 0.22) end
      elseif pola == "arpeggio" then
        local urut = { 1, 2, 3, 2 }
        local pilih = urut[(beat % 4) + 1]
        env = math.min(1, dalam / (laju * 0.012), math.max(0, (nadaPer - dalam) / (laju * 0.05)))
        sum = tambahNada(sum, frek[pilih], dalam, env * 0.55)
      elseif pola == "bass" then
        if beat == 0 then
          env = math.exp(-(dalam / laju) * 5) * math.min(1, dalam / (laju * 0.01))
          sum = tambahNada(sum, bass, dalam, env * 0.65)
        else
          env = math.min(1, dalam / (laju * 0.01), math.max(0, (nadaPer - dalam) / (laju * 0.04)))
          for _, f in ipairs(frek) do sum = tambahNada(sum, f, dalam, env * 0.2) end
        end
      else
        if beat == 0 or beat == 2 then
          env = math.exp(-(dalam / laju) * 7) * math.min(1, dalam / (laju * 0.008))
          sum = tambahNada(sum, bass, dalam, env * 0.7)
        elseif beat == 1 or beat == 3 then
          env = math.min(1, dalam / (laju * 0.008), math.max(0, (nadaPer - dalam) / (laju * 0.05)))
          for _, f in ipairs(frek) do sum = tambahNada(sum, f, dalam, env * 0.28) end
        end
      end
      if sum > 0.92 then sum = 0.92 elseif sum < -0.92 then sum = -0.92 end
      buffer[i] = math.floor(sum * 30000)
      if i % 4096 == 0 then napas() end
    end
  end
  return buffer, total
end

function DJL.studio.mainkanNada(pc, oktaf)
  if DJL.studioNada then
    pcall(function() DJL.studioNada.stop() end)
    pcall(function() DJL.studioNada.release() end)
    DJL.studioNada = nil
  end
  local laju = LAJU_AKOR
  local jumlah = math.floor(laju * 0.9)
  local frek = 16.3516 * 2 ^ ((pc + oktaf * 12) / 12)
  jalankanBertahap(function()
    local a = larik("Short", jumlah)
    for i = 0, jumlah - 1 do
      local t = i / laju
      local serang = math.min(1, t * 24)
      local lepas = math.exp(-t * 2.4)
      local fundamental = math.sin(2 * math.pi * frek * t)
      local harmonik = 0.34 * math.sin(4 * math.pi * frek * t) + 0.12 * math.sin(6 * math.pi * frek * t)
      local suara = (fundamental + harmonik) * serang * lepas * 0.62
      a[i] = math.floor(math.max(-0.92, math.min(0.92, suara)) * 30000)
      if i % 2048 == 0 then napas() end
    end
    return a
  end, function(ok, data)
    if not ok or not data then toast("Nada piano gagal dibuat") return end
    local tr = AudioTrack(3, laju, 4, 2, jumlah * 2, 0)
    local berhasil = pcall(function() tr.write(data, 0, jumlah) tr.play() end)
    if berhasil then
      DJL.studioNada = tr
      tunda(1100, function()
        if DJL.studioNada == tr then pcall(function() tr.release() end) DJL.studioNada = nil end
      end)
    else
      pcall(function() tr.release() end)
      toast("Nada piano tidak dapat diputar")
    end
  end)
end

function DJL.studio.putar(teksChord, teksTempo, pola, ketukPerChord)
  local bpm = tonumber(string.gsub(tostring(teksTempo or ""), ",", "."))
  if not bpm or bpm < 40 or bpm > 240 then toast("Tempo harus antara 40 sampai 240 BPM.") return end
  local daftar, gagal = DJL.studio.daftarChord(teksChord)
  if #daftar == 0 then toast("Masukkan minimal satu chord yang valid.") return end
  if #gagal > 0 then toast("Chord tidak dikenali: " .. table.concat(gagal, ", ")) return end
  DJL.hentikanStudio()
  toast("Menyiapkan iringan studio")
  jalankanBertahap(function()
    return DJL.studio.bangunAudio(daftar, bpm, pola, ketukPerChord)
  end, function(ok, buffer, total)
    if not ok or not buffer then toast("Audio studio gagal dibuat: " .. tostring(buffer)) return end
    local tr = AudioTrack(3, LAJU_AKOR, 4, 2, total * 2, 0)
    local berhasil = pcall(function() tr.write(buffer, 0, total) end)
    if not berhasil then pcall(function() tr.release() end) toast("Audio studio tidak dapat disiapkan.") return end
    DJL.studio.track = tr
    DJL.studio.jalan = true
    local main = pcall(function() tr.play() end)
    if not main then DJL.hentikanStudio() toast("Pemutaran studio gagal.") return end
    toast("Studio memutar " .. #daftar .. " chord, " .. angka(bpm, 0) .. " BPM, pola " .. DJL.studio.namaPola[pola])
    tunda(math.floor(total * 1000 / LAJU_AKOR) + 300, function()
      if DJL.studio.track == tr then DJL.hentikanStudio() toast("Iringan studio selesai") end
    end)
  end)
end

function DJL.studio.tampil()
  local editChord = E("Urutan chord, contoh C G Am F", pengaturan.studioProgresi)
  local editTempo = E("Tempo BPM, 40 sampai 240", pengaturan.studioTempo, true)
  local editKetuk = E("Ketukan per chord, 1 sampai 16", pengaturan.studioKetuk, true)
  local pilihan = {}
  for i, v in ipairs(DJL.studio.pola) do pilihan[i] = DJL.studio.namaPola[v] end
  local idx = 1
  for i, v in ipairs(DJL.studio.pola) do if v == pengaturan.studioPola then idx = i end end
  local spinner = buatSpinner(pilihan, idx, function(pos)
    pengaturan.studioPola = DJL.studio.pola[pos] or "balok"
    simpanPengaturan()
  end)
  local function simpan()
    pengaturan.studioProgresi = tostring(editChord.getText().toString())
    pengaturan.studioTempo = tostring(editTempo.getText().toString())
    pengaturan.studioKetuk = tostring(editKetuk.getText().toString())
    simpanPengaturan()
    toast("Progresi chord dan tempo disimpan")
  end
  layarForm("Studio Chord Virtual", function() DJL.hentikanStudio() menuUtama() end,
    T("Masukkan urutan chord dipisahkan spasi atau koma. Contoh: C G Am F", 15), editChord,
    T("Tempo permainan", 15), editTempo,
    T("Durasi setiap chord dalam ketukan", 15), editKetuk,
    T("Pilih pola iringan", 15), spinner,
    T("Tombol chord cepat", 15),
    B("Tambahkan C", function() editChord.append(" C") end),
    B("Tambahkan Dm", function() editChord.append(" Dm") end),
    B("Tambahkan Em", function() editChord.append(" Em") end),
    B("Tambahkan F", function() editChord.append(" F") end),
    B("Tambahkan G", function() editChord.append(" G") end),
    B("Tambahkan Am", function() editChord.append(" Am") end),
    B("Tambahkan Bdim", function() editChord.append(" Bdim") end),
    T("Piano oktaf rendah, C2 sampai B2", 15),
    B("C2", function() DJL.studio.mainkanNada(0, 2) end),
    B("Cis 2", function() DJL.studio.mainkanNada(1, 2) end),
    B("D2", function() DJL.studio.mainkanNada(2, 2) end),
    B("Dis 2", function() DJL.studio.mainkanNada(3, 2) end),
    B("E2", function() DJL.studio.mainkanNada(4, 2) end),
    B("F2", function() DJL.studio.mainkanNada(5, 2) end),
    B("Fis 2", function() DJL.studio.mainkanNada(6, 2) end),
    B("G2", function() DJL.studio.mainkanNada(7, 2) end),
    B("Gis 2", function() DJL.studio.mainkanNada(8, 2) end),
    B("A2", function() DJL.studio.mainkanNada(9, 2) end),
    B("Ais 2", function() DJL.studio.mainkanNada(10, 2) end),
    B("B2", function() DJL.studio.mainkanNada(11, 2) end),
    T("Piano oktaf tinggi, C4 sampai B4", 15),
    B("C4", function() DJL.studio.mainkanNada(0, 4) end),
    B("Cis 4", function() DJL.studio.mainkanNada(1, 4) end),
    B("D4", function() DJL.studio.mainkanNada(2, 4) end),
    B("Dis 4", function() DJL.studio.mainkanNada(3, 4) end),
    B("E4", function() DJL.studio.mainkanNada(4, 4) end),
    B("F4", function() DJL.studio.mainkanNada(5, 4) end),
    B("Fis 4", function() DJL.studio.mainkanNada(6, 4) end),
    B("G4", function() DJL.studio.mainkanNada(7, 4) end),
    B("Gis 4", function() DJL.studio.mainkanNada(8, 4) end),
    B("A4", function() DJL.studio.mainkanNada(9, 4) end),
    B("Ais 4", function() DJL.studio.mainkanNada(10, 4) end),
    B("B4", function() DJL.studio.mainkanNada(11, 4) end),
    B("Simpan progresi", function() simpan() end),
    B("Putar iringan", function()
      pengaturan.studioProgresi = tostring(editChord.getText().toString())
      pengaturan.studioTempo = tostring(editTempo.getText().toString())
      pengaturan.studioKetuk = tostring(editKetuk.getText().toString())
      simpanPengaturan()
      DJL.studio.putar(pengaturan.studioProgresi, pengaturan.studioTempo, pengaturan.studioPola, pengaturan.studioKetuk)
    end),
    B("Ulangi progresi dari awal", function()
      DJL.studio.putar(tostring(editChord.getText().toString()), tostring(editTempo.getText().toString()), pengaturan.studioPola, tostring(editKetuk.getText().toString()))
    end),
    B("Jeda", function()
      if DJL.studio.track and DJL.studio.jalan then pcall(function() DJL.studio.track.pause() end) DJL.studio.jalan = false toast("Iringan dijeda") else toast("Belum ada iringan yang diputar") end
    end),
    B("Lanjutkan", function()
      if DJL.studio.track and not DJL.studio.jalan then local ok = pcall(function() DJL.studio.track.play() end) DJL.studio.jalan = ok if ok then toast("Iringan dilanjutkan") end else toast("Tidak ada iringan yang dijeda") end
    end),
    B("Berhenti", function() DJL.hentikanStudio() toast("Iringan dihentikan") end),
    B("Kembali", function() DJL.hentikanStudio() menuUtama() end))
end

menuUtama = function()
  local butir, aksi = {}, {}
  butir[#butir + 1] = "Pilih lagu"
  aksi[#aksi + 1] = function() pilihLagu() end
  butir[#butir + 1] = "Riwayat lagu"
  aksi[#aksi + 1] = function() menuRiwayat() end
  butir[#butir + 1] = "Studio Chord Virtual"
  aksi[#aksi + 1] = function() DJL.studio.tampil() end
  if DJL.lagu then
    butir[#butir + 1] = "Lagu terakhir: " .. DJL.lagu.nama
    aksi[#aksi + 1] = function() menuLagu(DJL.lagu) end
  end
  butir[#butir + 1] = "Pengaturan"
  aksi[#aksi + 1] = function() menuPengaturan() end
  layarDaftar({
    judul = NAMA_EKSTENSI,
    butir = butir,
    pilih = function(i) aksi[i]() end,
    labelKembali = "Tutup",
    kembali = function() tutupSemua() end })
end

local function teksStatus()
  local nama = ps.sumber[ps.idx].nama
  local sl = "Lagu tidak bisa diputar."
  if ps.player then
    if not ps.siapLagu then
      sl = "Lagu sedang disiapkan."
    elseif ps.lagu then
      sl = "Lagu sedang diputar."
    else
      sl = "Lagu berhenti."
    end
  end
  local sm = "Metronom mati."
  if ps.metOn then sm = "Metronom nyala." end
  local teks = "Lagu: " .. ps.item.nama .. "\n" .. sl .. " " .. sm .. "\nTempo " .. angka(ps.tempo, 1) .. " BPM, dari " .. nama .. ". Fase " .. tostring(math.floor(ps.fase)) .. " ms. Volume lagu " .. pengaturan.volLagu .. ", klik " .. pengaturan.volKlik .. ", bunyi " .. NAMA_BUNYI[pengaturan.bunyi] .. ". Birama: " .. teksBirama() .. "."
  if ps.peta then
    if ps.ikutPeta then
      teks = teks .. "\nMetronom mengikuti peta tempo."
    else
      teks = teks .. "\nPeta tempo tersedia, metronom tidak mengikutinya."
    end
  end
  return teks
end

local function perbarui(pesan)
  if ps and ps.segarkan then ps.segarkan() end
  if pesan then toast(pesan) end
end

local function ulangMetronom()
  if ps and ps.metOn then MT.mulai() end
end

local function volumeLagu()
  if ps and ps.player then
    local v = (tonumber(pengaturan.volLagu) or 80) / 100
    pcall(function() ps.player.setVolume(v, v) end)
  end
end

local function aturMetronom(nyala, diam)
  ps.metOn = nyala
  if nyala then
    if not MT.mulai() then
      perbarui(nil)
      return
    end
  else
    MT.hentikan()
  end
  if not diam then
    if nyala then
      perbarui("Metronom nyala, tempo " .. angka(ps.tempo, 1))
    else
      perbarui("Metronom mati")
    end
  end
end

local function aturLagu(nyala, diam)
  if not ps.player then
    if not diam then perbarui("Lagu tidak bisa diputar") end
    return false
  end
  if not ps.siapLagu then
    if not diam then perbarui("Lagu masih disiapkan, coba sebentar lagi") end
    return false
  end
  if nyala then
    local ok = pcall(function() ps.player.start() end)
    if not ok then
      perbarui("Lagu gagal diputar")
      return false
    end
    ps.lagu = true
  else
    pcall(function() ps.player.pause() end)
    ps.lagu = false
  end
  if ps.metOn then
    MT.mulai()
    if ps.ikutPeta then ps.idxLangkah = nil end
  end
  if not diam then
    if nyala then perbarui("Lagu diputar") else perbarui("Lagu dijeda") end
  end
  return true
end

local function ubahTempo(nilai)
  if nilai < 30 then nilai = 30 elseif nilai > 300 then nilai = 300 end
  ps.tempo = nilai
  ps.ikutPeta = false
  ulangMetronom()
  perbarui(nil)
end

local function gantiSumber()
  ps.idx = ps.idx % #ps.sumber + 1
  local s = ps.sumber[ps.idx]
  ps.tempo = s.bpm
  ps.t0 = s.t0 or ps.awal
  ps.fase = 0
  ps.ikutPeta = false
  ulangMetronom()
  perbarui("Sumber tempo " .. s.nama .. ", " .. angka(s.bpm, 1))
end

local function putarDariAwal()
  if not ps.player or not ps.siapLagu then
    toast("Lagu tidak tersedia")
    return
  end
  ps.setelahSeek = function()
    aturLagu(true, true)
    perbarui("Lagu diputar dari awal")
  end
  pcall(function() ps.player.seekTo(0) end)
end

local function lompat(ms)
  if not ps.player or not ps.siapLagu then
    toast("Lagu tidak tersedia")
    return
  end
  local pos = 0
  pcall(function() pos = ps.player.getCurrentPosition() end)
  local baru = math.max(0, pos + ms)
  ps.setelahSeek = function()
    if ps.lagu then ulangMetronom() end
  end
  pcall(function() ps.player.seekTo(baru) end)
  if ms > 0 then toast("Maju") else toast("Mundur") end
end

local function tandaiKetukan()
  if not (ps.player and ps.lagu) then
    toast("Putar lagunya dulu, lalu tandai saat ketukan terdengar")
    return
  end
  local pos = 0
  pcall(function() pos = ps.player.getCurrentPosition() end)
  ps.t0 = pos
  ps.fase = 0
  ps.satuIdx = 0
  ps.ikutPeta = false
  ulangMetronom()
  perbarui("Ketukan ditandai sebagai ketukan satu")
end

local function tandaiKetukanSatu()
  if not (ps.player and ps.lagu) then
    toast("Putar lagunya dulu, lalu tandai saat ketukan satu terdengar")
    return
  end
  local pos = 0
  pcall(function() pos = ps.player.getCurrentPosition() end)
  local periode = 60000 / ps.tempo
  local bar = jumlahBirama()
  local n = math.floor((pos - ps.t0 - ps.fase) / periode + 0.5)
  ps.satuIdx = n % bar
  ulangMetronom()
  perbarui("Ketukan satu ditandai")
end

local function layarTempoPemutar()
  layarTempo({
    ambil = function() return ps.tempo end,
    setel = function(v) ubahTempo(v) end,
    info = function(v) return "Tempo " .. angka(v, 1) .. " BPM, sumber " .. ps.sumber[ps.idx].nama end,
    tambahan = { { "Ganti sumber tempo", function() gantiSumber() end } },
    kembali = function() pemutarUtama() end })
end

local layarFase

local function layarKetukPemutar()
  layarKetuk({
    judul = "Ketuk tempo mengikuti lagu",
    ketuk = ps.ketuk,
    butuhLagu = true,
    saatPakai = function(r, k)
      local total, jml = 0, 0
      for _, i in ipairs(r.idx) do
        total = total + (k.pos[i] - r.periode * r.k[i])
        jml = jml + 1
      end
      ps.t0 = total / jml
      ps.tempo = r.bpm
      ps.fase = 0
      ps.satuIdx = 0
      ps.ikutPeta = false
      ulangMetronom()
      perbarui("Metronom memakai hasil ketukan, " .. angka(r.bpm, 1))
      pemutarUtama()
    end,
    kembali = function() layarFase() end })
end

layarFase = function()
  local tv = T("", 16)
  local sl
  local function info()
    tv.setText("Fase: " .. tostring(math.floor(ps.fase)) .. " milidetik. Fase lebih besar menggeser klik lebih lambat dari lagu.")
  end
  local awal = math.floor(ps.fase / 5 + 0.5) * 5
  if awal < -250 then awal = -250 elseif awal > 250 then awal = 250 end
  local etFase = E("Fase dalam milidetik, boleh minus", string.format("%d", math.floor(ps.fase)), true)
  sl = buatSlider({
    min = -250, max = 250, langkah = 5, nilai = awal,
    label = function(v) return "Fase: " .. tostring(v) .. " milidetik" end,
    saatUbah = function(v)
      ps.fase = v
      etFase.setText(string.format("%d", v))
      info()
      tundaKunci("fase", 350, ulangMetronom)
    end })
  info()
  layarForm("Atur fase dan ketukan", function() pemutarUtama() end, tv, sl.view, etFase,
    B("Terapkan angka fase", function()
      local t = string.gsub(pangkas(tostring(etFase.getText())), ",", ".")
      local v = tonumber(t)
      if not v then
        toast("Angka tidak valid")
        return
      end
      ps.fase = v
      local s = math.floor(v / 5 + 0.5) * 5
      if s < -250 then s = -250 elseif s > 250 then s = 250 end
      sl.setNilai(s)
      info()
      ulangMetronom()
      perbarui("Fase " .. tostring(math.floor(v)))
    end),
    B("Tandai ketukan sekarang", function() tandaiKetukan() end),
    B("Tandai ketukan satu sekarang", function() tandaiKetukanSatu() end),
    B("Ketuk tempo mengikuti lagu", function() layarKetukPemutar() end),
    B("Kembali", function() pemutarUtama() end))
end

local function layarPeta()
  local butir, aksi = {}, {}
  local status = "tidak mengikuti peta"
  if ps.ikutPeta then status = "mengikuti peta" end
  butir[#butir + 1] = "Metronom ikut peta tempo: " .. status .. ", ketuk untuk mengganti"
  aksi[#aksi + 1] = function()
    ps.ikutPeta = not ps.ikutPeta
    if ps.ikutPeta then
      ps.idxLangkah = nil
      jagaPeta(ps)
      perbarui("Metronom mengikuti peta tempo")
    else
      perbarui("Metronom tidak lagi mengikuti peta tempo")
    end
    layarPeta()
  end
  butir[#butir + 1] = "Baca ringkasan peta tempo"
  aksi[#aksi + 1] = function()
    dialogPesan("Peta tempo", teksPeta(ps.peta, ps.transposisi), { { "Kembali", function() layarPeta() end } }, function() layarPeta() end)
  end
  for i, b in ipairs(ps.peta) do
    local label = "Bagian " .. i .. ", " .. waktuTeks(b.mulaiMs) .. " sampai " .. waktuTeks(b.akhirMs) .. ", "
    if b.tipe == "bertahap" then
      label = label .. "bertahap dari " .. angka(b.bpm, 1) .. " ke " .. angka(b.bpm2, 1) .. " BPM"
    else
      label = label .. "tetap " .. angka(b.bpm, 1) .. " BPM"
    end
    butir[#butir + 1] = label .. ", ketuk untuk melompat ke sana"
    aksi[#aksi + 1] = function()
      if not ps.player or not ps.siapLagu then
        toast("Lagu tidak tersedia")
        return
      end
      ps.setelahSeek = function() ulangMetronom() end
      pcall(function() ps.player.seekTo(math.floor(b.mulaiMs)) end)
      toast("Bagian " .. i .. ", tempo " .. angka(b.bpm, 1))
    end
  end
  layarDaftar({
    judul = "Peta tempo",
    butir = butir,
    pilih = function(i) aksi[i]() end,
    kembali = function() pemutarUtama() end })
end

local function layarLompat()
  layarDaftar({
    judul = "Lompat dalam lagu",
    butir = { "Mundur 10 detik", "Maju 10 detik", "Putar dari awal lagu" },
    pilih = function(i)
      if i == 1 then
        lompat(-10000)
      elseif i == 2 then
        lompat(10000)
      else
        putarDariAwal()
      end
    end,
    kembali = function() pemutarUtama() end })
end

layarSuara = function(kembali)
  if type(kembali) ~= "function" then kembali = function() menuPengaturan() end end
  local slLagu = buatSlider({
    min = 0, max = 100, langkah = 5, nilai = (tonumber(pengaturan.volLagu) or 80),
    label = function(v) return "Volume lagu: " .. tostring(v) end,
    saatUbah = function(v)
      pengaturan.volLagu = tostring(v)
      volumeLagu()
      tundaKunci("simpanVol", 600, simpanPengaturan)
    end })
  local slKlik = buatSlider({
    min = 0, max = 100, langkah = 5, nilai = (tonumber(pengaturan.volKlik) or 80),
    label = function(v) return "Volume klik metronom: " .. tostring(v) end,
    saatUbah = function(v)
      pengaturan.volKlik = tostring(v)
      if ps and ps.track then pcall(function() ps.track.setVolume(v / 100) end) end
      tundaKunci("simpanVol", 600, simpanPengaturan)
    end })
  local aktifBunyi = daftarBunyiAktif()
  local namaBunyi, idxBunyi = {}, 1
  for i, v in ipairs(aktifBunyi) do
    namaBunyi[i] = NAMA_BUNYI[v]
    if v == pengaturan.bunyi then idxBunyi = i end
  end
  local spBunyi = buatSpinner(namaBunyi, idxBunyi, function(p)
    local v = aktifBunyi[p]
    if v == pengaturan.bunyi then return end
    pengaturan.bunyi = v
    simpanPengaturan()
    MT.siapkan(function() end)
    tundaKunci("ulangMet", 300, ulangMetronom)
  end)
  local nilaiBirama = { "0", "2", "3", "4", "6" }
  local namaBirama = { "Tanpa aksen, semua ketukan sama", "2 ketukan per birama", "3 ketukan per birama", "4 ketukan per birama", "6 ketukan per birama" }
  local idxBirama = 1
  for i, v in ipairs(nilaiBirama) do
    if v == pengaturan.birama then idxBirama = i end
  end
  local spBirama = buatSpinner(namaBirama, idxBirama, function(p)
    local v = nilaiBirama[p]
    if v == pengaturan.birama then return end
    pengaturan.birama = v
    simpanPengaturan()
    tundaKunci("ulangMet", 300, ulangMetronom)
  end)
  layarForm("Suara metronom dan volume", kembali,
    slLagu.view, slKlik.view,
    T("Bunyi metronom:", 15), spBunyi,
    T("Birama dan aksen, bunyi tinggi di ketukan pertama:", 15), spBirama,
    B("Dengarkan bunyi metronom saat ini", function() MT.uji() end),
    B("Sampel metronom sendiri", function() menuSampel(function() layarSuara(kembali) end) end),
    B("Kembali", function() kembali() end))
end

local function pemutarKeluar()
  local item = ps and ps.item
  MT.bersihkan()
  if item then menuLagu(item) else menuUtama() end
end

pemutarUtama = function()
  if not ps then
    menuUtama()
    return
  end
  local tv = T(teksStatus(), 15)
  ps.segarkan = function() pcall(function() tv.setText(teksStatus()) end) end
  local butir, aksi = {}, {}
  local function tambah(label, fn)
    butir[#butir + 1] = label
    aksi[#aksi + 1] = fn
  end
  tambah("Putar atau jeda lagu", function() aturLagu(not ps.lagu, false) end)
  tambah("Putar atau hentikan metronom", function() aturMetronom(not ps.metOn, false) end)
  tambah("Putar atau hentikan lagu dan metronom sekaligus", function()
    if ps.lagu or ps.metOn then
      ps.metOn = false
      MT.hentikan()
      aturLagu(false, true)
      perbarui("Lagu dan metronom dihentikan")
    else
      ps.metOn = true
      if not aturLagu(true, true) then MT.mulai() end
      if ps.metOn then
        perbarui("Lagu dan metronom diputar")
      else
        perbarui(nil)
      end
    end
  end)
  tambah("Putar lagu dari awal", function() putarDariAwal() end)
  tambah("Atur tempo", function() layarTempoPemutar() end)
  tambah("Atur fase dan ketukan", function() layarFase() end)
  tambah("Atur suara dan volume", function() layarSuara(function() pemutarUtama() end) end)
  if ps.peta then
    tambah("Peta tempo", function() layarPeta() end)
  end
  tambah("Lompat dalam lagu", function() layarLompat() end)
  tambah("Dengarkan akor kunci", function() menuAkor(ps.item, function() pemutarUtama() end) end)
  tambah("Pakai angka tempo ini sebagai hasil periksa", function()
    simpanTeks("fix_" .. idLagu(ps.item), tostring(ps.tempo))
    perbarui("Tempo " .. angka(ps.tempo, 1) .. " disimpan sebagai hasil periksa")
  end)
  layarDaftar({
    judul = "Pemutar lagu dan metronom",
    atas = tv,
    butir = butir,
    pilih = function(i) aksi[i]() end,
    labelKembali = "Tutup dan hentikan",
    kembali = function() pemutarKeluar() end })
end

layarPemutar = function(item)
  local h = ambilHasil(item)
  local sumber = {}
  local t0Offline = nil
  if h.off then t0Offline = h.off.t0Ms end
  if h.fix then sumber[#sumber + 1] = { nama = "hasil periksamu", bpm = h.fix, t0 = t0Offline } end
  if h.off then sumber[#sumber + 1] = { nama = "offline", bpm = h.off.bpm, t0 = h.off.t0Ms } end
  if h.on then sumber[#sumber + 1] = { nama = tostring(h.on.sumber or "FreqBlog"), bpm = h.on.bpm, t0 = t0Offline } end
  if #sumber == 0 then
    toast("Belum ada hasil tempo. Analisis lagunya dulu.")
    menuLagu(item)
    return
  end
  MT.bersihkan()
  local awal = 30000
  if h.off and h.off.awalMs then
    awal = h.off.awalMs
  elseif h.on and h.on.seg and h.on.seg > 0 then
    awal = h.on.seg * 1000
  end
  ps = { item = item, sumber = sumber, idx = 1, awal = awal, fase = 0, lagu = false, metOn = false, satuIdx = 0, peta = h.peta, ikutPeta = false, siapLagu = false, transposisi = ambilTranspose(item), ketuk = { t = {}, pos = {} } }
  if h.peta then ps.langkah = bangunLangkah(h.peta) end
  ps.tempo = sumber[1].bpm
  ps.t0 = sumber[1].t0 or awal
  ps.mulaiOtomatis = (pengaturan.mulaiPutar == "awal")
  local mp = MediaPlayer()
  local okMp, errMp = pcall(function()
    if item.path == nil or item.path == "" then error("Berkas lagu tidak diketahui") end
    mp.setDataSource(item.path)
  end)
  if okMp then
    ps.player = mp
    mp.setOnPreparedListener(MediaPlayer.OnPreparedListener({
      onPrepared = function(m)
        if not ps or not ps.player then return end
        ps.siapLagu = true
        local durMs = 0
        pcall(function() durMs = m.getDuration() end)
        if durMs > 0 and ps.awal > durMs - 10000 then
          ps.awal = 0
          if not sumber[1].t0 then ps.t0 = 0 end
        end
        volumeLagu()
        local mulaiDi = ps.awal
        if ps.mulaiOtomatis then
          mulaiDi = 0
          ps.setelahSeek = function()
            aturLagu(true, true)
            perbarui("Lagu siap dan diputar dari awal")
          end
        end
        pcall(function() m.seekTo(mulaiDi) end)
        perbarui(nil)
      end }))
    mp.setOnSeekCompleteListener(MediaPlayer.OnSeekCompleteListener({
      onSeekComplete = function(m)
        local fn = ps and ps.setelahSeek
        if fn then
          ps.setelahSeek = nil
          fn()
        end
        if ps and ps.ikutPeta then ps.idxLangkah = nil end
      end }))
    mp.setOnCompletionListener(MediaPlayer.OnCompletionListener({
      onCompletion = function(m)
        if ps then
          ps.lagu = false
          if ps.metOn and ps.metSinkron then
            ps.metOn = false
            MT.hentikan()
          end
          perbarui("Lagu selesai")
        end
      end }))
    local oke = pcall(function() mp.prepareAsync() end)
    if not oke then ps.player = nil end
  else
    pcall(function() mp.release() end)
    ps.galatLagu = tostring(errMp)
  end
  MT.siapkan(function() end)
  pemutarUtama()
  if not ps.player then
    toast("Lagu tidak bisa diputar, tetapi metronom tetap bisa dipakai.")
  end
end

local function judulSlot(slot)
  if slot == "sampelAksen" then return "Klik 1, ketukan pertama, bunyi tinggi" end
  return "Klik 2, ketukan lainnya, bunyi rendah"
end

local function statusSampel(slot)
  if pengaturan[slot] == "" then return "belum dipilih" end
  return pengaturan[slot .. "Nama"]
end

local menuSlotSampel

local function pasangSampel(slot, path, nama, kembali)
  toast("Memeriksa sampel")
  jalankanBertahap(function()
    return SM.muat(path)
  end, function(ok, data, info)
    if not ok or not data then
      local sebab = tostring(info)
      if not ok then sebab = tostring(data) end
      dialogPesan("Sampel tidak bisa dipakai", sebab, { { "Kembali", function() menuSlotSampel(slot, kembali) end } }, function() menuSlotSampel(slot, kembali) end)
      return
    end
    local salinan = SM.salin(path, slot)
    pengaturan[slot] = salinan
    pengaturan[slot .. "Nama"] = nama
    pengaturan.bunyi = "sampel"
    local tambahan = ""
    if slot == "sampelAksen" and jumlahBirama() < 2 then
      pengaturan.birama = "4"
      tambahan = " Aksen dinyalakan, 4 ketukan per birama."
    end
    simpanPengaturan()
    DJL.sampel = DJL.sampel or {}
    DJL.sampel[slot] = { path = salinan, data = data, info = info }
    toast("Sampel dipilih untuk " .. judulSlot(slot) .. ": " .. nama .. ". Panjang asli " .. tostring(info.durAsliMs) .. " milidetik, dipakai " .. tostring(info.durPakaiMs) .. " milidetik, laju " .. tostring(info.srAsli) .. " hertz. Bunyi bawaan dimatikan." .. tambahan)
    menuSlotSampel(slot, kembali)
  end)
end

local function dengarkanSampel(slot)
  jalankanBertahap(function()
    return SM.cache(slot)
  end, function(ok, data)
    if not ok then
      tampilGalat("Sampel tidak bisa dibaca", tostring(data))
      return
    end
    if not data then
      toast("Sampel tidak bisa dibaca")
      return
    end
    local n = #data + 2000
    local blok = larik("Short", n)
    for i = 1, #data do blok[i - 1] = data[i] end
    local oke, tr = pcall(function()
      local t = AudioTrack(3, LAJU, 4, 2, n * 2, 0)
      t.write(blok, 0, n)
      pcall(function() t.setVolume(tonumber(pengaturan.volKlik) / 100) end)
      t.play()
      return t
    end)
    if not oke then
      toast("Sampel gagal diputar: " .. tostring(tr))
      return
    end
    tunda(math.floor(n * 1000 / LAJU) + 250, function()
      pcall(function() tr.stop() end)
      pcall(function() tr.release() end)
    end)
  end)
end

menuSlotSampel = function(slot, kembali)
  layarDaftar({
    judul = judulSlot(slot) .. ": " .. statusSampel(slot),
    butir = { "Pilih berkas sampel", "Dengarkan sampel ini", "Hapus sampel ini" },
    pilih = function(i)
      if i == 1 then
        bukaPicker({
          judul = "Pilih sampel metronom",
          pathAwal = pengaturan.terakhir,
          filter = function(nama, ukuran)
            local ekst = string.lower(string.match(nama, "%.(%w+)$") or "")
            return EKSTENSI[ekst] == true and ukuran > 0 and ukuran <= 3145728
          end,
          onPilih = function(e) pasangSampel(slot, e.path, e.nama, kembali) end,
          onBatal = function() menuSlotSampel(slot, kembali) end })
      elseif i == 2 then
        if pengaturan[slot] == "" then
          toast("Sampel belum dipilih")
        else
          dengarkanSampel(slot)
        end
      else
        pengaturan[slot] = ""
        pengaturan[slot .. "Nama"] = ""
        if pengaturan.sampel == "" and pengaturan.sampelAksen == "" and pengaturan.bunyi == "sampel" then pengaturan.bunyi = "cubase" end
        if DJL.sampel then DJL.sampel[slot] = nil end
        simpanPengaturan()
        toast("Sampel dihapus")
        menuSlotSampel(slot, kembali)
      end
    end,
    kembali = function() menuSampel(kembali) end })
end

menuSampel = function(kembali)
  if type(kembali) ~= "function" then kembali = function() menuPengaturan() end end
  layarDaftar({
    judul = "Sampel metronom sendiri",
    butir = {
      judulSlot("sampelAksen") .. ": " .. statusSampel("sampelAksen") .. ", pilih untuk mengatur",
      judulSlot("sampel") .. ": " .. statusSampel("sampel") .. ", pilih untuk mengatur",
      "Dengarkan bunyi metronom saat ini" },
    pilih = function(i)
      if i == 1 then
        menuSlotSampel("sampelAksen", kembali)
      elseif i == 2 then
        menuSlotSampel("sampel", kembali)
      else
        MT.uji()
      end
    end,
    kembali = function() kembali() end })
end

layarPenyedia = function(kembali, awal)
  if type(kembali) ~= "function" then kembali = function() menuPengaturan() end end
  local kode = { "freqblog", "audo" }
  local nama = { "FreqBlog", "Audo AI" }
  local buffer = { freqblog = pengaturan.token, audo = pengaturan.tokenAudo }
  local pilih = 1
  if pengaturan.penyedia == "audo" then pilih = 2 end
  if awal then
    buffer = awal.buffer
    pilih = awal.pilih
  end
  local info = T("", 15)
  local edit = E("", buffer[kode[pilih]])
  local btnLink = nil
  local function perbaruiTampilan()
    if pilih == 1 then
      edit.setHint("Kunci FreqBlog")
      info.setText("FreqBlog butuh kunci. Kuota gratisnya 25 analisis per bulan, berkas maksimal 15 MB.")
    else
      edit.setHint("Kunci Audo AI, opsional")
      info.setText("Audo AI boleh tanpa kunci: kosong berarti jalur gratis, jatah 20 per hari. Dengan kunci, batas laju lebih longgar. Berkas maksimal 95 MB.")
    end
    if btnLink then btnLink.setText("Dapatkan kunci " .. nama[pilih]) end
  end
  local spinner = buatSpinner(nama, pilih, function(p)
    if p == pilih then return end
    buffer[kode[pilih]] = bersihKunci(edit.getText())
    pilih = p
    edit.setText(buffer[kode[p]] or "")
    perbaruiTampilan()
  end)
  btnLink = B("Dapatkan kunci " .. nama[pilih], function()
    if pilih == 1 then bukaTautan(LAMAN_KUNCI) else bukaTautan(LAMAN_KUNCI_AUDO) end
  end)
  local function simpan()
    buffer[kode[pilih]] = bersihKunci(edit.getText())
    local kf = buffer.freqblog or ""
    local ka = buffer.audo or ""
    local sebab = nil
    if kf ~= "" and not kunciValid(kf) then
      sebab = "Kunci FreqBlog harus berupa huruf, angka, garis bawah atau tanda hubung, minimal 12 karakter, tanpa spasi."
    elseif ka ~= "" and not kunciValid(ka) then
      sebab = "Kunci Audo AI harus berupa huruf, angka, garis bawah atau tanda hubung, minimal 12 karakter, tanpa spasi."
    end
    if sebab then
      local ulang = function() layarPenyedia(kembali, { buffer = buffer, pilih = pilih }) end
      dialogPesan("Kunci tidak valid", sebab, { { "Perbaiki", ulang } }, ulang)
      return
    end
    pengaturan.penyedia = kode[pilih]
    pengaturan.token = kf
    pengaturan.tokenAudo = ka
    simpanPengaturan()
    toast("Tersimpan, penyedia aktif " .. nama[pilih])
    kembali()
  end
  perbaruiTampilan()
  layarForm("Penyedia analisis online", kembali,
    T("Pilih penyedia yang dipakai:", 15), spinner,
    T("Kunci API untuk penyedia terpilih:", 15), edit,
    info,
    B("Tempel kunci dari papan klip", function()
      local c = bersihKunci(bacaClipboard())
      if c == "" then
        toast("Papan klip kosong")
      else
        edit.setText(c)
        toast("Kunci ditempel, pilih Simpan")
      end
    end),
    btnLink,
    B("Simpan", function() simpan() end),
    B("Batal", function() kembali() end))
end

menuPengaturan = function()
  local function statusKunci(k)
    if k == "" then return "belum diisi" end
    return "terisi, berakhiran " .. string.sub(k, -4)
  end
  local sampelTeks = "belum dipilih"
  if pengaturan.sampel ~= "" or pengaturan.sampelAksen ~= "" then sampelTeks = "sudah dipilih" end
  local mulaiTeks = "lagu menunggu, mulai dari bagian yang dianalisis"
  if pengaturan.mulaiPutar == "awal" then mulaiTeks = "lagu langsung diputar dari awal" end
  local butir, aksi = {}, {}
  butir[#butir + 1] = "Penyedia analisis online: " .. namaSingkat(pengaturan.penyedia) .. ". Kunci FreqBlog " .. statusKunci(pengaturan.token) .. ". Kunci Audo AI " .. statusKunci(pengaturan.tokenAudo) .. ". Pilih untuk mengatur"
  aksi[#aksi + 1] = function() layarPenyedia() end
  butir[#butir + 1] = "Suara metronom dan volume: bunyi " .. NAMA_BUNYI[pengaturan.bunyi] .. ", pilih untuk mengatur"
  aksi[#aksi + 1] = function() layarSuara(function() menuPengaturan() end) end
  butir[#butir + 1] = "Sampel metronom sendiri: " .. sampelTeks .. ", pilih untuk mengatur"
  aksi[#aksi + 1] = function() menuSampel(function() menuPengaturan() end) end
  butir[#butir + 1] = "Saat pemutar dibuka: " .. mulaiTeks .. ", pilih untuk mengganti"
  aksi[#aksi + 1] = function()
    if pengaturan.mulaiPutar == "awal" then pengaturan.mulaiPutar = "analisis" else pengaturan.mulaiPutar = "awal" end
    simpanPengaturan()
    menuPengaturan()
    if pengaturan.mulaiPutar == "awal" then
      toast("Pemutar sekarang memutar lagu dari awal secara otomatis")
    else
      toast("Pemutar sekarang menunggu, mulai dari bagian yang dianalisis")
    end
  end
  butir[#butir + 1] = "Folder lagu tambahan untuk Cari semua, pilih untuk mengubah"
  aksi[#aksi + 1] = function()
    dialogIsian({
      judul = "Folder lagu tambahan",
      pesan = "Tulis alamat folder, pisahkan dengan titik koma. Penyimpanan internal dan kartu memori sudah ikut dicari otomatis.",
      awal = pengaturan.folder,
      simpan = function(teks)
        pengaturan.folder = pangkas(teks)
        simpanPengaturan()
        DJL.daftar = nil
        toast("Folder disimpan")
        menuPengaturan()
      end,
      batal = function() menuPengaturan() end })
  end
  butir[#butir + 1] = "Muat ulang daftar lagu untuk Cari semua"
  aksi[#aksi + 1] = function()
    DJL.daftar = nil
    muatDaftarLagu(true, function(d)
      toast(#d .. " lagu dimuat")
      menuPengaturan()
    end)
  end
  layarDaftar({
    judul = "Pengaturan",
    butir = butir,
    pilih = function(i) aksi[i]() end,
    kembali = function() menuUtama() end })
end

pcall(function()
  local p = package.searchpath("main", package.path)
  if p then DJL.base = string.match(p, "^(.*/)") end
end)
DJL.batal = false
DJL.batalOnline = false
DJL.sibuk = false
DJL.analisisJalan = false
DJL.siapJalan = false
DJL.antreKlik = {}
DJL.klik = nil
DJL.kunciYield = 0
muatPengaturan()
tutupDialog()
menuUtama()
