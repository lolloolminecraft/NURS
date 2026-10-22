(function () {
    'use strict';

    if (window.lampaFamilyModeLoaded) return;
    window.lampaFamilyModeLoaded = true;

    var KEY = 'lampa_family_';
    var MAX_CACHE = 350;
    var CACHE_LIFE = 14 * 24 * 60 * 60 * 1000;
    var queue = [];
    var busy = 0;
    var waiting = {};
    var cache = {};
    var rules = {};
    var kids = false;
    var childAge = 12;
    var pin = '1234';
    var menuButton = null;
    var ruleMenuButton = null;
    var originals = {};
    var allowedPages = {
        main: true,
        category: true,
        category_full: true,
        full: true,
        online: true,
        torrents: true,
        episodes: true
    };
    var blockedNames = /^(?:south park|rick and morty|family guy|american dad|bojack horseman|big mouth|happy tree friends|solar opposites|paradise pd|f is for family|invincible|robot chicken|attack on titan|shingeki no kyojin|атака титанов|demon slayer|kimetsu no yaiba|клинок,? рассекающий демонов|истребитель демонов|chainsaw man|человек[ -]бензопила|death note|тетрадь смерти|berserk|берсерк|tokyo ghoul|токийский гуль|jujutsu kaisen|магическая битва|elfen lied|hellsing|corpse party)(?:$|[\s:–—-])/i;
    var sensitiveWords = /\b(adult animation|adult cartoon|explicit content|sexual violence|sexual content|graphic violence|gore|slasher|torture|profanity|swearing|swear words|strong language|foul language|vulgar language|extreme horror|blood splatter)\b|нецензурн|матерн|ненормативн|жестокост|пытк|расчленен/i;

    function storage() {
        return window.Lampa.Storage;
    }

    function save(name, value) {
        storage().set(KEY + name, value);
    }

    function read(name, fallback) {
        return storage().get(KEY + name, fallback);
    }

    function message(value) {
        if (window.Lampa && Lampa.Noty) Lampa.Noty.show(value);
    }

    function titleOf(card) {
        return String(card.title || card.name || card.original_title || card.original_name || 'Мультфильм');
    }

    function encoded(value) {
        try {
            return encodeURIComponent(decodeURIComponent(String(value || '')));
        } catch (error) {
            return encodeURIComponent(String(value || ''));
        }
    }

    function typeOf(card, fallback) {
        if (card && (card.media_type === 'movie' || card.media_type === 'tv')) return card.media_type;
        if (fallback === 'movie' || fallback === 'tv') return fallback;
        return card && (card.first_air_date || card.original_name || card.name) ? 'tv' : 'movie';
    }

    function identity(card, type) {
        return typeOf(card, type) + ':' + String(card.id);
    }

    function genreIds(card) {
        var list = card.genre_ids || card.genres || [];
        return list.map(function (entry) {
            return Number(typeof entry === 'object' ? entry.id : entry);
        });
    }

    function contains(list, value) {
        return list.indexOf(value) !== -1;
    }

    function anime(card) {
        var countries = card.origin_country || card.production_countries || [];
        var fromJapan = countries.some(function (item) {
            return item === 'JP' || item.iso_3166_1 === 'JP';
        });
        return card.original_language === 'ja' || fromJapan;
    }

    function ratingNumber(value) {
        var raw = String(value || '').toUpperCase().trim().replace(/\s+/g, '');
        if (!raw || raw === 'NR' || raw === 'UNRATED' || raw === 'NOTRATED') return null;
        var known = {
            'G': 0, 'U': 0, 'TV-Y': 0, 'TV-Y7': 7, 'TV-G': 0,
            'PG': 8, 'TV-PG': 10, 'PG-13': 13, 'TV-14': 14,
            'PG12': 12, '12A': 12, '14A': 14, '15A': 15,
            'R': 17, 'NC-17': 18, 'TV-MA': 18, 'M': 15,
            'MA15+': 15, 'R18+': 18, 'R21': 21, 'ALL': 0
        };
        if (Object.prototype.hasOwnProperty.call(known, raw)) return known[raw];
        var matched = raw.match(/^(?:AGES?|AGE|FSK|USK)?(0|3|6|7|8|9|10|12|13|14|15|16|17|18|21)\+?$/);
        return matched ? Number(matched[1]) : null;
    }

    function certifications(details, type) {
        var allowedCountries = ['KZ', 'RU', 'US', 'GB'];
        var source = type === 'tv' ? details.content_ratings : details.release_dates;
        var data = source && source.results ? source.results : [];
        var ages = [];
        data.forEach(function (region) {
            if (!contains(allowedCountries, region.iso_3166_1)) return;
            var ratings = type === 'tv' ? [region.rating] : (region.release_dates || []).map(function (part) { return part.certification; });
            ratings.forEach(function (value) {
                var age = ratingNumber(value);
                if (age !== null) ages.push(age);
            });
        });
        return ages.length ? Math.max.apply(Math, ages) : null;
    }

    function keywordsOf(details) {
        var holder = details.keywords || {};
        return (holder.keywords || holder.results || []).map(function (item) {
            return String(item.name || '').toLowerCase();
        });
    }

    function exactRule(card, type) {
        return rules[identity(card, type)] || null;
    }

    function adultTitle(card) {
        return blockedNames.test(String(card.original_title || card.original_name || titleOf(card)).trim()) || blockedNames.test(titleOf(card).trim());
    }

    function quickBlock(card, rule) {
        if (!card || card.adult === true) return true;
        if (rule && rule.status === 'block') return true;
        if (adultTitle(card)) return true;
        if (rule && rule.status === 'allow') return false;
        var genres = genreIds(card);
        return !!(genres.length && !contains(genres, 16));
    }

    function isAdultContent(card, details, type) {
        if (card.adult === true || details.adult === true || adultTitle(card) || adultTitle(details)) return true;
        var certified = Object.prototype.hasOwnProperty.call(details, '_rating') ? details._rating : certifications(details, type);
        if (certified !== null && certified >= 16) return true;
        return Object.prototype.hasOwnProperty.call(details, '_sensitive') ? details._sensitive : keywordsOf(details).some(function (word) { return sensitiveWords.test(word); });
    }

    function pickAllowed(card, details, type) {
        if (!card || !details) return false;
        var rule = exactRule(card, type);
        if (rule && rule.status === 'block') return false;
        if (isAdultContent(card, details, type)) return false;
        if (rule && rule.status === 'allow') {
            return childAge >= Number(rule.fromAge || 0) && childAge <= Number(rule.toAge == null ? 15 : rule.toAge);
        }
        var genres = genreIds(details);
        return contains(genres, 16) || contains(genreIds(card), 16);
    }

    function runQueue() {
        while (busy < 6 && queue.length) {
            busy++;
            (function (job) {
                job(function () {
                    busy--;
                    runQueue();
                });
            })(queue.shift());
        }
    }

    function metadata(card, type, callback) {
        type = typeOf(card, type);
        var key = identity(card, type);
        var saved = cache[key];
        if (saved && saved.time + CACHE_LIFE > Date.now()) return callback(saved.details);
        if (waiting[key]) {
            waiting[key].push(callback);
            return;
        }
        waiting[key] = [callback];
        queue.push(function (done) {
            var url = type + '/' + encodeURIComponent(card.id) + '?append_to_response=' + (type === 'tv' ? 'content_ratings,keywords' : 'release_dates,keywords');
            var finish = function (details) {
                if (details) {
                    cache[key] = {time: Date.now(), details: {
                        id: details.id,
                        adult: details.adult,
                        genres: details.genres,
                        original_language: details.original_language,
                        origin_country: details.origin_country,
                        production_countries: details.production_countries,
                        original_name: details.original_name,
                        original_title: details.original_title,
                        name: details.name,
                        title: details.title,
                        overview: details.overview,
                        _rating: certifications(details, type),
                        _sensitive: keywordsOf(details).some(function (word) { return sensitiveWords.test(word); })
                    }};
                    var keys = Object.keys(cache);
                    if (keys.length > MAX_CACHE) {
                        keys.sort(function (a, b) { return cache[a].time - cache[b].time; });
                        keys.slice(0, keys.length - MAX_CACHE).forEach(function (old) { delete cache[old]; });
                    }
                    save('cache', cache);
                }
                var callbacks = waiting[key] || [];
                delete waiting[key];
                callbacks.forEach(function (cb) { cb(details || null); });
                done();
            };
            try {
                Lampa.Api.sources.tmdb.get(url, {}, finish, function () { finish(null); }, {life: 60 * 24 * 7});
            } catch (error) {
                finish(null);
            }
        });
        runQueue();
    }

    function permitted(card, type, callback) {
        if (!card || !card.id) return callback(false);
        type = typeOf(card, type);
        var rule = rules[identity(card, type)];
        if (quickBlock(card, rule)) return callback(false);
        metadata(card, type, function (details) {
            callback(pickAllowed(card, details, type));
        });
    }

    function filterCards(cards, type, max, callback) {
        var selected = (cards || []).slice(0, max || 20);
        var accepted = [];
        var remaining = selected.length;
        if (!remaining) return callback([]);
        selected.forEach(function (card, index) {
            permitted(card, type, function (allow) {
                if (allow) {
                    card.source = 'tmdb';
                    accepted.push({index: index, card: card});
                }
                remaining--;
                if (!remaining) {
                    accepted.sort(function (a, b) { return a.index - b.index; });
                    callback(accepted.map(function (item) { return item.card; }));
                }
            });
        });
    }

    function sectionList() {
        var date = new Date();
        var today = date.getFullYear() + '-' + ('0' + (date.getMonth() + 1)).slice(-2) + '-' + ('0' + date.getDate()).slice(-2);
        var base = '&include_adult=false&vote_count.gte=8';
        return [
            {title: 'Новые мультфильмы', url: 'discover/movie?with_genres=16&sort_by=primary_release_date.desc&primary_release_date.lte=' + today + '&include_adult=false&vote_count.gte=2'},
            {title: 'Популярные мультфильмы', url: 'discover/movie?with_genres=16&sort_by=popularity.desc' + base},
            {title: 'Новые мультсериалы', url: 'discover/tv?with_genres=16&sort_by=first_air_date.desc&first_air_date.lte=' + today + base},
            {title: 'Семейные мультфильмы', url: 'discover/movie?with_genres=16,10751&sort_by=popularity.desc' + base},
            {title: 'Приключения', url: 'discover/movie?with_genres=16,12&sort_by=popularity.desc' + base},
            {title: 'Весёлые мультфильмы', url: 'discover/movie?with_genres=16,35&sort_by=popularity.desc' + base},
            {title: 'Лучшие мультсериалы', url: 'discover/tv?with_genres=16&sort_by=vote_average.desc&vote_count.gte=50&include_adult=false'},
            {title: 'Фантастика и приключения', url: 'discover/movie?with_genres=16,878&sort_by=popularity.desc' + base},
            {title: 'Мультфильмы с высоким рейтингом', url: 'discover/movie?with_genres=16&sort_by=vote_average.desc&vote_count.gte=100&include_adult=false'}
        ];
    }

    function childUrl(value) {
        var text = String(value || '');
        if (/^discover\/(movie|tv)\?/.test(text) && /(?:\?|&)with_genres=16(?:&|,|$)/.test(text)) return text;
        return 'discover/movie?with_genres=16&sort_by=popularity.desc&include_adult=false';
    }

    function fetchSection(section, page, callback, error, retries) {
        retries = retries || 0;
        var type = section.url.indexOf('/tv?') >= 0 ? 'tv' : 'movie';
        var url = section.url + '&page=' + (page || 1);
        Lampa.Api.sources.tmdb.get(url, {}, function (data) {
            filterCards(data.results, type, 20, function (results) {
                if (!results.length && retries < 1 && data.total_pages > page) {
                    fetchSection(section, page + 1, callback, error, retries + 1);
                    return;
                }
                data.results = results.slice(0, 16);
                data.title = section.title;
                data.url = section.url;
                data.source = 'tmdb';
                data.page = page;
                callback(data);
            });
        }, function () {
            if (error) error();
        }, {life: 60 * 24});
    }

    function childRows(params, success, failure) {
        var remaining = sectionList();
        if (params.url === 'tv') remaining = remaining.filter(function (row) { return row.url.indexOf('/tv?') !== -1; });
        function next(ok, fail) {
            if (!remaining.length) return fail();
            var take = remaining.splice(0, 3);
            var resolved = [];
            var pending = take.length;
            take.forEach(function (section, index) {
                var finish = function (data) {
                    if (data && data.results && data.results.length) resolved.push({index: index, data: data});
                    pending--;
                    if (!pending) {
                        resolved.sort(function (a, b) { return a.index - b.index; });
                        if (resolved.length) ok(resolved.map(function (item) { return item.data; }));
                        else next(ok, fail);
                    }
                };
                fetchSection(section, 1, finish, function () { finish(null); });
            });
        }
        next(success, failure);
        return next;
    }

    function childList(params, success, failure) {
        params = params || {};
        var query = String(params.url || '');
        if (/^search\/(movie|tv)/.test(query) && params.query) {
            var searchedType = query.indexOf('/tv') >= 0 ? 'tv' : 'movie';
            Lampa.Api.sources.tmdb.get('search/' + searchedType, {query: encoded(params.query), page: params.page || 1}, function (data) {
                filterCards(data.results, searchedType, 20, function (results) {
                    data.results = results;
                    success(data);
                });
            }, failure);
            return;
        }
        fetchSection({title: params.title || 'Мультфильмы', url: childUrl(query)}, params.page || 1, success, failure);
    }

    function childSearch(params, callback) {
        Lampa.Api.sources.tmdb.get('search/multi', {query: encoded(params.query)}, function (data) {
            var cards = (data.results || []).filter(function (card) {
                return card.media_type === 'movie' || card.media_type === 'tv';
            });
            filterCards(cards, null, 20, function (allowed) {
                var movie = allowed.filter(function (item) { return typeOf(item) === 'movie'; });
                var tv = allowed.filter(function (item) { return typeOf(item) === 'tv'; });
                var rows = [];
                if (movie.length) rows.push({title: 'Мультфильмы', type: 'movie', results: movie});
                if (tv.length) rows.push({title: 'Мультсериалы', type: 'tv', results: tv});
                callback(rows);
            });
        }, function () { callback([]); });
    }

    function childDiscovery() {
        return {
            title: 'Только мультфильмы',
            params: {save: false},
            search: childSearch,
            onSelect: function (params, close) {
                close();
                Lampa.Activity.push({component: 'full', id: params.element.id, method: typeOf(params.element), source: 'tmdb', card: params.element});
            },
            onMore: function (params, close) {
                close();
                Lampa.Activity.push({component: 'category_full', title: 'Поиск мультфильмов', url: 'search/' + (params.data.type || 'movie'), query: params.query, source: 'tmdb', page: 1});
            }
        };
    }

    function safePage(object) {
        if (!object || !object.component) return true;
        return !!allowedPages[object.component];
    }

    function home() {
        return {component: 'main', title: 'Мультфильмы для детей', source: 'tmdb', url: ''};
    }

    function refreshHome() {
        try {
            Lampa.Activity.replace(kids ? home() : {component: 'main', title: 'Главная', source: read('previous_source', 'tmdb'), url: ''}, true);
        } catch (error) {
            Lampa.Activity.push(kids ? home() : {component: 'main', title: 'Главная', url: ''});
        }
    }

    function applyMode() {
        document.body.classList.toggle('lampa-family-kids', kids);
        if (menuButton) menuButton.find('.menu__text').text(kids ? 'Выйти из детского режима' : 'Включить детский режим');
        if (ruleMenuButton) ruleMenuButton.toggle(kids);
    }

    function setMode(active) {
        if (kids === active) return;
        if (active) save('previous_source', Lampa.Storage.field('source') || 'tmdb');
        kids = active;
        save('enabled', kids);
        applyMode();
        if (Lampa.Menu && Lampa.Menu.close) Lampa.Menu.close();
        refreshHome();
        message(kids ? 'Детский режим включён' : 'Обычный режим включён');
    }

    function editText(heading, value, callback, secret) {
        var previous = Lampa.Controller && Lampa.Controller.enabled ? Lampa.Controller.enabled().name : '';
        Lampa.Input.edit({title: heading, value: value || '', free: true, nosave: true, keyboard: 'lampa', password: !!secret, layout: secret ? 'nums' : undefined}, function (entry) {
            if (previous && Lampa.Controller) Lampa.Controller.toggle(previous);
            callback(String(entry || '').trim());
        });
    }

    function askPin(callback) {
        editText('Введите PIN-код', '', function (value) {
            if (value === pin) callback();
            else if (value) message('Неверный PIN-код');
        }, true);
    }

    function changePin() {
        askPin(function () {
            editText('Новый PIN-код: 4–8 цифр', '', function (value) {
                if (!/^\d{4,8}$/.test(value)) return message('PIN должен содержать 4–8 цифр');
                editText('Повторите новый PIN-код', '', function (second) {
                    if (second !== value) return message('PIN-коды не совпадают');
                    pin = value;
                    save('pin', pin);
                    message('PIN-код изменён');
                }, true);
            }, true);
        });
    }

    function chooseChildAge() {
        askPin(function () {
            var items = [];
            for (var age = 6; age <= 15; age++) items.push({title: age + ' лет' + (age === childAge ? ' ✓' : ''), age: age});
            Lampa.Select.show({title: 'Возраст ребёнка', items: items, onSelect: function (item) {
                childAge = item.age;
                save('age', childAge);
                if (kids) refreshHome();
                message('Возраст: ' + childAge + ' лет');
            }});
        });
    }

    function saveRule(card, type, status, fromAge, toAge) {
        type = typeOf(card, type);
        function store() {
            var key = identity(card, type);
            rules[key] = {
                id: card.id,
                type: type,
                title: titleOf(card),
                status: status,
                fromAge: fromAge,
                toAge: toAge
            };
            save('rules', rules);
            if (kids) refreshHome();
            message((status === 'block' ? 'Заблокировано: ' : 'Разрешено: ') + titleOf(card));
        }
        if (status === 'block') return store();
        if (adultTitle(card) || card.adult === true) return message('Этот мультфильм нельзя разрешить: взрослый контент');
        metadata(card, type, function (details) {
            if (!details) return message('Не удалось проверить мультфильм. Разрешение не сохранено');
            if (isAdultContent(card, details, type)) return message('16+/18+ или взрослый контент: разрешение запрещено');
            store();
        });
    }

    function setAgeRange(card, type) {
        var starts = [0, 3, 6, 7, 9, 12, 13, 14, 15].map(function (n) {
            return {title: 'От ' + n + ' лет', value: n};
        });
        Lampa.Select.show({title: 'С какого возраста показывать?', items: starts, onSelect: function (start) {
            var ends = [];
            for (var n = Math.max(6, start.value); n <= 15; n++) ends.push({title: 'До ' + n + ' лет', value: n});
            Lampa.Select.show({title: 'До какого возраста показывать?', items: ends, onSelect: function (end) {
                saveRule(card, type, 'allow', start.value, end.value);
            }});
        }});
    }

    function editRule(card, type) {
        var key = identity(card, type);
        var items = [
            {title: 'Разрешить для возраста 6–15', action: 'allow'},
            {title: 'Разрешить с выбором возраста', action: 'range'},
            {title: 'Заблокировать мультфильм', action: 'block'}
        ];
        if (rules[key]) items.push({title: 'Удалить исключение', action: 'delete'});
        Lampa.Select.show({title: titleOf(card), items: items, onSelect: function (item) {
            if (item.action === 'range') return setAgeRange(card, type);
            if (item.action === 'delete') {
                delete rules[key];
                save('rules', rules);
                if (kids) refreshHome();
                return message('Правило удалено');
            }
            saveRule(card, type, item.action, 6, 15);
        }});
    }

    function searchException() {
        askPin(function () {
            editText('Название мультфильма', '', function (query) {
                if (query.length < 2) return;
                message('Ищем мультфильмы...');
                Lampa.Api.sources.tmdb.get('search/multi', {query: encoded(query)}, function (result) {
                    var items = (result.results || []).filter(function (card) {
                        return card.media_type === 'movie' || card.media_type === 'tv';
                    }).slice(0, 20).map(function (card) {
                        return {title: titleOf(card) + ' (' + (card.release_date || card.first_air_date || '').slice(0, 4) + ')', card: card};
                    });
                    if (!items.length) return message('Ничего не найдено');
                    Lampa.Select.show({title: 'Выберите мультфильм', items: items, onSelect: function (entry) {
                        editRule(entry.card, typeOf(entry.card));
                    }});
                }, function () { message('Ошибка поиска'); });
            });
        });
    }

    function manageExceptions() {
        askPin(function () {
            var items = Object.keys(rules).map(function (key) {
                var rule = rules[key];
                return {title: rule.title + ' — ' + (rule.status === 'block' ? 'скрыт' : rule.fromAge + '–' + rule.toAge + ' лет'), rule: rule};
            });
            if (!items.length) return message('Список исключений пуст');
            Lampa.Select.show({title: 'Мои исключения', items: items, onSelect: function (item) {
                editRule({id: item.rule.id, title: item.rule.title, media_type: item.rule.type}, item.rule.type);
            }});
        });
    }

    function openFamilyTools() {
        Lampa.Select.show({
            title: 'Управление мультфильмами',
            items: [
                {title: 'Найти и запретить или разрешить', action: 'find'},
                {title: 'Мои запреты и разрешения', action: 'rules'},
                {title: 'Изменить возраст ребёнка', action: 'age'},
                {title: 'Изменить PIN-код', action: 'pin'}
            ],
            onSelect: function (item) {
                if (item.action === 'find') searchException();
                if (item.action === 'rules') manageExceptions();
                if (item.action === 'age') chooseChildAge();
                if (item.action === 'pin') changePin();
            }
        });
    }

    function cardFromFullEvent(event) {
        var data = event && event.data || {};
        var active = Lampa.Activity.active() || {};
        var card = data.movie || data.card || data.object || active.movie || active.card || null;
        if (card && card.id) return card;
        return active.id ? {id: active.id, title: active.title, media_type: active.method} : null;
    }

    function injectFullActions(event) {
        if (!kids || !event || event.type !== 'complite' || !event.object || !event.object.activity || !event.object.activity.render) return;
        var card = cardFromFullEvent(event);
        if (!card || !card.id) return;
        var root = event.object.activity.render();
        if (!root || !root.find || root.find('.lampa-family-ban').length) return;
        var holder = root.find('.full-start-new__buttons, .full-start__buttons').first();
        if (!holder.length) holder = root.find('.view--torrent').parent();
        if (!holder.length) return;
        var type = typeOf(card);
        var current = exactRule(card, type);
        var ban = $('<div class="full-start__button selector lampa-family-ban"><svg viewBox="0 0 24 24" width="24" height="24"><path fill="currentColor" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm0 3a7 7 0 0 1 5.1 2.2l-9.9 9.9A7 7 0 0 1 12 5Zm0 14a7 7 0 0 1-5.1-2.2l9.9-9.9A7 7 0 0 1 12 19Z"/></svg><span>Заблокировать</span></div>');
        var allow = $('<div class="full-start__button selector lampa-family-allow"><svg viewBox="0 0 24 24" width="24" height="24"><path fill="currentColor" d="M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4Z"/></svg><span>Разрешить</span></div>');
        var edit = $('<div class="full-start__button selector lampa-family-edit"><span>Возраст / правило</span></div>');
        ban.on('hover:enter click', function (e) {
            if (e.type === 'click') e.preventDefault();
            askPin(function () { saveRule(card, type, 'block', 6, 15); });
        });
        allow.on('hover:enter click', function (e) {
            if (e.type === 'click') e.preventDefault();
            askPin(function () { saveRule(card, type, 'allow', 6, 15); });
        });
        edit.on('hover:enter click', function (e) {
            if (e.type === 'click') e.preventDefault();
            askPin(function () { editRule(card, type); });
        });
        holder.append(ban).append(allow).append(edit);
        if (current && current.status === 'block') ban.find('span').text('Заблокирован');
        if (current && current.status === 'allow') allow.find('span').text('Разрешён');
    }

    function addSetting(id, label, detail, callback) {
        Lampa.SettingsApi.addParam({
            component: 'family_mode',
            param: {name: 'family_mode_' + id, type: 'button'},
            field: {name: label, description: detail || ''},
            onChange: callback
        });
    }

    function settings() {
        Lampa.SettingsApi.addComponent({
            component: 'family_mode',
            name: 'Семейный режим',
            icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2a5 5 0 0 1 5 5 5 5 0 0 1-3 4.58V14h4a4 4 0 0 1 4 4v4H2v-4a4 4 0 0 1 4-4h4v-2.42A5 5 0 0 1 12 2Z"/></svg>'
        });
        addSetting('switch', 'Переключить режим', 'Обычное кино или только мультфильмы', function () {
            if (kids) askPin(function () { setMode(false); });
            else setMode(true);
        });
        addSetting('age', 'Возраст ребёнка', 'Сейчас ' + childAge + ' лет; максимум 15 лет', chooseChildAge);
        addSetting('pin', 'Изменить PIN-код', 'По умолчанию 1234', changePin);
        addSetting('add', 'Добавить разрешение или запрет', 'Найти мультфильм по названию', searchException);
        addSetting('manage', 'Управлять исключениями', 'Возраст, запрет, удаление', manageExceptions);
    }

    function pluginMenu() {
        if (!Lampa.Menu || !Lampa.Menu.addButton) return;
        var switchMode = function () {
            if (kids) askPin(function () { setMode(false); });
            else setMode(true);
        };
        var shield = '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 2 2 7v5c0 6 4 9 10 10 6-1 10-4 10-10V7L12 2Zm0 4 6 3v3c0 3-2 5-6 6-4-1-6-3-6-6V9l6-3Z"/></svg>';
        menuButton = Lampa.Menu.addButton(shield, 'Включить детский режим', switchMode);
        if (menuButton && menuButton.attr) {
            menuButton.attr('data-family-mode', '1');
        }
        var tools = function () {
            if (!kids) return;
            openFamilyTools();
        };
        ruleMenuButton = Lampa.Menu.addButton('<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 2 3 7v5c0 6 4 9 9 10 5-1 9-4 9-10V7Zm-1 5h2v6h-2Zm0 8h2v2h-2Z"/></svg>', 'Запретить / разрешить мультфильм', tools);
        if (ruleMenuButton && ruleMenuButton.attr) {
            ruleMenuButton.attr('data-family-mode', '1');
        }
        applyMode();
    }

    function wrapApi() {
        var api = Lampa.Api;
        ['main', 'category', 'list', 'search', 'full', 'favorite', 'menu', 'menuCategory', 'availableDiscovery', 'relise'].forEach(function (name) {
            originals[name] = api[name];
        });
        api.main = function (p, ok, fail) { return kids ? childRows(p || {}, ok, fail) : originals.main.apply(api, arguments); };
        api.category = function (p, ok, fail) { return kids ? childRows(p || {}, ok, fail) : originals.category.apply(api, arguments); };
        api.list = function (p, ok, fail) { return kids ? childList(p, ok, fail) : originals.list.apply(api, arguments); };
        api.search = function (p, ok) {
            if (!kids) return originals.search.apply(api, arguments);
            childSearch(p, function (rows) { ok({movie: rows.filter(function (r) { return r.type === 'movie'; })[0], tv: rows.filter(function (r) { return r.type === 'tv'; })[0]}); });
        };
        api.full = function (p, ok, fail) {
            if (!kids) return originals.full.apply(api, arguments);
            var card = p.card || {id: p.id, media_type: p.method};
            permitted(card, p.method, function (pass) {
                if (pass) {
                    p.source = 'tmdb';
                    originals.full.call(api, p, ok, fail);
                } else if (fail) fail({blocked: true});
            });
        };
        api.favorite = function (p, ok, fail) {
            if (!kids) return originals.favorite.apply(api, arguments);
            originals.favorite.call(api, p, function (data) {
                filterCards(data.results, null, 40, function (result) {
                    data.results = result;
                    if (result.length) ok(data);
                    else if (fail) fail();
                });
            }, fail);
        };
        api.menu = function (p, ok) {
            if (!kids) return originals.menu.apply(api, arguments);
            ok([{title: 'Мультфильмы', id: 16}]);
        };
        api.menuCategory = function (p, ok) {
            if (!kids) return originals.menuCategory.apply(api, arguments);
            ok(sectionList().map(function (item) { return {title: item.title, url: item.url}; }));
        };
        api.availableDiscovery = function () { return kids ? [childDiscovery()] : originals.availableDiscovery.apply(api, arguments); };
        api.relise = function (p, ok, fail) {
            if (!kids) return originals.relise.apply(api, arguments);
            fetchSection(sectionList()[0], (p && p.page) || 1, ok, fail);
        };
    }

    function wrapNavigation() {
        var activity = Lampa.Activity;
        var originalPush = activity.push;
        var originalReplace = activity.replace;
        activity.push = function (object) {
            if (!kids) return originalPush.apply(activity, arguments);
            if (!safePage(object)) return message('В детском режиме доступны только мультфильмы');
            if (object.component === 'category' || object.component === 'category_full') {
                object.source = 'tmdb';
                if (object.component === 'category') {
                    object.url = object.url === 'tv' ? 'tv' : 'movie';
                    object.title = 'Мультфильмы';
                } else if (!(/^search\/(movie|tv)/.test(String(object.url || '')) && object.query)) object.url = childUrl(object.url);
            }
            if (object.component === 'full' || object.component === 'online' || object.component === 'torrents' || object.component === 'episodes') {
                var card = object.card || object.movie || (Lampa.Activity.active() || {}).card;
                if (!card || !card.id) return message('Не удалось проверить возрастной рейтинг');
                return permitted(card, object.method || typeOf(card), function (pass) {
                    if (kids && pass) originalPush.call(activity, object);
                    else if (kids) message('Этот мультфильм недоступен в детском режиме');
                });
            }
            return originalPush.call(activity, object);
        };
        activity.replace = function (object, clear) {
            if (kids && object && object.component && !safePage(object)) return originalReplace.call(activity, home(), true);
            return originalReplace.apply(activity, arguments);
        };
        Lampa.Player.listener.follow('create', function (event) {
            if (!kids || !event || !event.abort) return;
            var screen = activity.active() || {};
            var card = event.data && (event.data.card || screen.movie || screen.card);
            if (!card || !card.id) return event.abort();
            var item = cache[identity(card, typeOf(card))];
            if (!item || !pickAllowed(card, item.details, typeOf(card))) event.abort();
        });
        Lampa.Listener.follow('activity', function (event) {
            if (!kids || !event || event.type !== 'start' || allowedPages[event.component]) return;
            setTimeout(function () {
                if (kids) originalReplace.call(activity, home(), true);
            }, 0);
        });
    }

    function wrapSearch() {
        if (!Lampa.Search || !Lampa.Search.open) return;
        var originalOpen = Lampa.Search.open;
        Lampa.Search.open = function (params) {
            if (!kids) return originalOpen.apply(Lampa.Search, arguments);
            var settings = params || {};
            settings.sources = [childDiscovery()];
            return originalOpen.call(Lampa.Search, settings);
        };
    }

    function protectSettings() {
        if (!Lampa.Controller || !Lampa.Controller.toggle) return;
        var originalToggle = Lampa.Controller.toggle;
        var unlocked = false;
        Lampa.Controller.toggle = function (name) {
            if (kids && !unlocked && (name === 'settings' || name === 'console')) {
                return askPin(function () {
                    unlocked = true;
                    originalToggle.call(Lampa.Controller, name);
                    unlocked = false;
                });
            }
            return originalToggle.apply(Lampa.Controller, arguments);
        };
    }

    function installStyle() {
        var style = document.createElement('style');
        style.textContent = 'body.lampa-family-kids .menu__item[data-action]:not([data-action="main"]):not([data-action="cartoon"]):not([data-family-mode="1"]){display:none!important}body.lampa-family-kids .menu__item[data-family-mode="1"]{display:flex!important}body.lampa-family-kids .search-source:not(:first-child){display:none!important}';
        document.head.appendChild(style);
    }

    function init() {
        kids = read('enabled', false) === true;
        childAge = Math.max(6, Math.min(15, Number(read('age', 12)) || 12));
        pin = String(read('pin', '1234'));
        rules = read('rules', {}) || {};
        cache = read('cache', {}) || {};
        installStyle();
        wrapApi();
        wrapNavigation();
        wrapSearch();
        protectSettings();
        settings();
        pluginMenu();
        Lampa.Listener.follow('full', injectFullActions);
        Lampa.Listener.follow('menu', function (event) {
            if (!kids || !event || event.type !== 'action' || !event.abort) return;
            if (event.action === 'main' || event.action === 'cartoon' || event.action === 'family_mode_toggle' || event.action === 'family_mode_rules') return;
            var el = event.element || event.item || event.target;
            if (el && $(el).closest && $(el).closest('[data-family-mode="1"]').length) return;
            event.abort();
        });
        applyMode();
        if (kids) setTimeout(refreshHome, 500);
        message('Lampa Family Mode 1.1 установлен');
    }

    if (window.appready) init();
    else Lampa.Listener.follow('app', function (event) { if (event.type === 'ready') init(); });
})();
