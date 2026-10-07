{include file="html_head.tpl"}
{include file="header.tpl"}

<script src="//{$domain}/lib/lightbox/js/lightbox.js"></script>
<link href="//{$domain}/lib/lightbox/css/lightbox.css" rel="stylesheet" />

<style>
    .put-text {
        text-decoration: underline;
        cursor: pointer;
        left: {$left}px;
    }
</style>

<script>
    $(document).ready(function() { 

        $('.put-text').on('click', function(e) {
            $(e.target).parent().parent().find('.comment').val($(e.target).html({$placeholder}));
        });

        {*
        $("#appeals-table").tablesorter(
            {
                headers: {
                    0: { sorter: false },
                    5: { sorter: false },
                    6: { sorter: false }
                }
            }
        );
        *}

        $('.monitor').on('click', function(e) {
            $(e.target).parent().toggleClass('correct');

            var
                total = $(e.target).parent().parent().find('tr').length,
                correct = $(e.target).parent().parent().find('tr.correct').length;            

            $(e.target).parent().parent().parent().parent().find('.status').prop('checked', false);
            $(e.target).parent().parent().parent().parent().find('.status_4').prop('checked', true);

            if (total == correct) {
                $(e.target).parent().parent().parent().parent().find('.status_5').prop('checked', true);
            } else if (correct == 0) {
                $(e.target).parent().parent().parent().parent().find('.status_3').prop('checked', true);
            }
            // fixme: вообще говоря, если зачтённые КП совпадают с теми,
            // что были загружены изначально, надо ставить "отклонена", а не "частично удовлетворена"
        });

        // resort even rows (hidden ones; so called "content rows") after sorting the odd ones
        // todo: find a better way of implementing "onSort".
        // MutationObserver? some way to bind "after all" event handler?
        $('th').on('click', function(e) {
            window.setTimeout(function() {
                $('.appeal-details').each(function(i, el) {
                    $(el).insertAfter(
                        $('.appeal-header[appeal-id=' + $(el).attr('appeal-id') + ']')
                    );
                });
            }, 100);
        });

        $('.appeal-header').on('click', function(e) {
            if ($(e.target).is(':checkbox')) { return true; }

            $('.appeal-header').not($(e.target).closest('tr')).removeClass('row-current');
            $('.appeal-details').not($(e.target).closest('tr').next()).hide();

            $(e.target).closest('tr').next().toggle();
            $(e.target).closest('tr').toggleClass('row-current');
        });

        $('#action-pending').on('click', function(e) {
            var list = JSON.stringify(
                $.map(
                    $('.action-checkbox').toArray(),
                    function(a,b) {
                        out = new Object;
                        out[$(a).attr('appeal-id')] = ($(a).prop('checked') ? 1 : 0);
                        return out;
                    }
                )
            );
            window.location = '?action=pending&list=' + list;
            return false;
        });
    }); 
</script>

<style>
    .appeal-content {
        background-color: #eee;
        padding: 10px;
    }

    table.tablesorter tr td table tr.monitor td {
        border-bottom: 2px solid white;
        color: white;
        background-color: red;
        cursor: pointer;
    }

    table.tablesorter tr td table tr.correct td {
        background-color: green;
    }

    .row-current {
        border: 2px solid orange;
    }
</style>
    
<div id="content">

    <h1>
        Апелляции
        {if $appeals_allowed && $competition.results_ready}
            <span style="color: green;">(приём идёт)</span>
        {else}
            <span style="color: red;">(приём закрыт)</span>
        {/if}
    </h1>

    <form style="float: left; clear: none; padding-bottom: 2pt;">
        <input type=hidden name=sort value="{$sort}" />
        <input type=hidden name=desc value="{$desc}" />
        <input type=hidden name=mode value="{$mode}" />
        <select name="cat_id" onchange="this.form.submit();">
            <option value="">Все категории
            {foreach from=$categories key=cat_id item=category}
                <option {if $current_category == $cat_id}selected{/if} value="{$cat_id}">{$category.name}
            {/foreach}
        </select>
    </form>

    <form style="float: left; clear: none; padding-bottom: 2pt;">
        <input type=hidden name=sort value="{$sort}" />
        <input type=hidden name=desc value="{$desc}" />
        <input type=hidden name=cat_id value="{$current_category}" />
        <input type=radio name=mode value=1 {if $mode == 1}checked{/if} onchange="this.form.submit();">Новые
        <input type=radio name=mode value=2 {if $mode == 2}checked{/if} onchange="this.form.submit();">Обработанные
    </form>

    <table id="appeals-table" class="tablesorter">
        <thead>
            <tr class="table-header">
                <th>
                    <input
                        type="checkbox"
                        onclick="$('.action-checkbox').prop('checked', $(this).prop('checked'));"
                    />
                    <strong>все</strong>
                </td>
                <th>
                    {$lp = "?cat_id={$current_category}&mode={$mode}"}
                    <a href={$lp}&sort=id{if ($sort=='id') && !$desc}&desc=1{/if}>id</a>
                    &nbsp;&nbsp;&nbsp;
                </td>
                <th>
                    <a href={$lp}&sort=status{if ($sort=='status') && !$desc}&desc=1{/if}>
                        Статус
                    </a>
                </td>
                <th>
                    <a href={$lp}&sort=snumber{if ($sort=='snumber') && !$desc}&desc=1{/if}>
                        Номер команды
                    </a>
                </td>
                <th>
                    <a href={$lp}&sort=cat_id{if ($sort=='cat_id') && !$desc}&desc=1{/if}>
                        Категория
                    </a>
                </td>
                <th>
                    КП + всплывающая подсказка с легендой 3 строчки
                </td>
                <th data-sort="string">
                    Текст
                </td>
                <th>
                    Ответ
                </td>
            </tr>
        </thead>
        <tbody>

            {foreach from=$appeals key=appeal_count item=appeal}
                <tr
                    id="appeal-{$appeal.id}"
                    class="appeal-header"
                    appeal-id="{$appeal.id}"
                    style="cursor: pointer;"
                >
                    <td><input type="checkbox" class="action-checkbox" appeal-id="{$appeal.id}" /></td>
                    <td>{$appeal.id}</td>
                    <td>
                        {if $appeal.status > 2}<strike>{/if}
                        {if $appeal.status == 1}
                            отправлена
                        {else if $appeal.status == 2}
                            рассматривается
                        {else if $appeal.status == 3}
                            отклонена
                        {else if $appeal.status == 4}
                            удовлетворена частично
                        {else if $appeal.status == 5}
                            удовлетворена
                        {/if}
                        {if $appeal.status > 2}</strike>{/if}
                    </td>
                    <td>
                        {strip}
                            {$categories[$appeal.team.cat_id].prefix}
                            {if $appeal.team.snumber|strlen == 1}0{/if}
                            {$appeal.team.snumber}
                        {/strip}
                    </td>
                    <td>{$categories[$appeal.team.cat_id].name}</td>
                    <td>
                        {foreach from=$appeal.cps item=cp_id name=cp_list}
                            <span title="
                                {$cps[$cp_id].legend_address|escape:'quotes'}
                                {$cps[$cp_id].legend_desc|escape:'quotes'}
                                {$cps[$cp_id].legend_quest|escape:'quotes'}
                                ">{$cps[$cp_id].number}</span>
                            {if !$smarty.foreach.cp_list.last},{/if}
                        {/foreach}
                    </td>
                    <td>{$appeal.content|truncate:80}</td>
                    <td>{$appeal.resolution|truncate:80}</td>
                </tr>
                <tr
                    class="appeal-details row-current"
                    appeal-id="{$appeal.id}"
                    style="display: none;"
                >
                    <td colspan="8">
                        <div class="appeal-content">
                            <form method="post">
                                <input type=hidden name=sort value="{$sort}" />
                                <input type=hidden name=desc value="{$desc}" />
                                <input type=hidden name=mode value="{$mode}" />
                                <input type=hidden name=next value="{$appeals[$appeal_count+1].id}" />
                                <input type="hidden" name="action" value="save">
                                <input type="hidden" name="cat_id" value="{$current_category}">
                                <p style="padding-bottom: 10px; font-size: 125%;">
                                    Апелляция от команды
                                    {strip}
                                        {$categories[$appeal.team.cat_id].prefix}
                                        {if $appeal.team.snumber|strlen == 1}0{/if}
                                        {$appeal.team.snumber}
                                    {/strip}
                                    &laquo;{$appeal.team.name}&raquo;:
                                </p>
                                <p style="padding-bottom: 10px; font-size: 125%;">{$appeal.content|nl2br}</p>
                                {if $appeal.cps}
                                    <table style="margin-bottom: 10px; font-size: 150%; width: 22em;">
                                        {foreach from=$appeal.cps item=cp}
                                            <tr
                                                class="monitor {if $appeal.team.cps[$cp].is_correct}correct{/if}"
                                                id="cp{$cps[$cp].id}"
                                            >
                                                <td>{$cps[$cp].number}</td>
                                                {if $answers[$appeal.team.id][$cp].answer_photo}
                                                    <td>
                                                        <a
                                                            rel=lightbox[{$appeal.id}-answer]
                                                            href="{$answers[$appeal.team.id][$cp].photo_url}"
                                                            target="_blank"
                                                        >
                                                            {$cps[$cp].answer}
                                                        </a>
                                                        <img
                                                            src="{$answers[$appeal.team.id][$cp].photo_url}"
                                                            width="1"
                                                            height="1"
                                                        />
                                                    </td>
                                                {else}
                                                    <td>{$cps[$cp].answer}</td>
                                                {/if}
                                                <td><em>{$answers[$appeal.team.id][$cp].answer}</em></td>
                                            </tr>
                                        {/foreach}
                                    </table>
                                {/if}
                                <p>
                                    {foreach from=$appeal.photos item=photo_uri}
                                        <a href="{$photo_uri}" rel=lightbox[{$appeal.id}-appeal] target="_blank">
                                            <img src="{$photo_uri}" height="50" />
                                        </a>
                                    {/foreach}
                                </p>
                                <p style="color: blue;">
                                    <input
                                        class="status"
                                        type="radio"
                                        name="status"
                                        {if $appeal.status == 1 || $appeal.status == 2}checked{/if}
                                        value="2"/>
                                    рассматривается
                                </p>
                                <p style="color: red;">
                                    <input
                                        class="status status_3"
                                        type="radio"
                                        name="status"
                                        {if $appeal.status == 3}checked{/if}
                                        value="3"/>
                                    отклонена
                                </p>
                                <p style="color: orange;">
                                    <input
                                        class="status status_4"
                                        type="radio"
                                        name="status"
                                        {if $appeal.status == 4}checked{/if}
                                        value="4"/>
                                    удовлетворена частично
                                </p>
                                <p style="color: green;">
                                    <input
                                        class="status status_5"
                                        type="radio"
                                        name="status"
                                        {if $appeal.status == 5}checked{/if}
                                        value="5"/>
                                    удовлетворена
                                </p>
                                <p>
                                    <textarea
                                        class="comment"
                                        name="resolution"
                                        placeholder="Комментарий судьи"
                                        style="width: 32em; height: 8em; margin-top: 10px;"
                                    >{$appeal.resolution}</textarea>
                                </p>
                                <p>
                                    «<span class="put-text">Техническая ошибка исправлена, КП зачтен.</span>»
                                    <br/>
                                    «<span class="put-text">По результатам апелляции КП зачтен.</span>»
                                </p>
                                <p>
                                    <input type="hidden" name="id" value="{$appeal.id}">
                                    <input type="hidden" name="team_id" value="{$appeal.team.id}">
                                    <input type="hidden" name="cps" id="cps">
                                    <script>
                                        function onSaveClick(el) {
                                            if ($(el).parent().parent().find('.comment').val() == '') {
                                                alert('Пустой комментарий :-(');
                                                return false;
                                            }

                                            $(el).
                                            parent().
                                            parent().
                                            find('#cps').
                                            val(
                                                JSON.stringify(
                                                    $.map(
                                                        $(el).
                                                        parent().
                                                        parent().
                                                        parent().
                                                        find('table tr.monitor').
                                                        toArray(),
                                                        function(a,b) {
                                                            out = new Object;
                                                            out[$(a).attr('id')] = (
                                                                $(a).hasClass('correct') ?
                                                                1 :
                                                                0
                                                            );
                                                            return out;
                                                        }
                                                    )
                                                )
                                            );

                                            if (
                                                $(el).
                                                parent().
                                                parent().
                                                find('.status_5').
                                                prop('checked') &&
                                                $(el).
                                                parent().
                                                parent().
                                                find('.monitor').
                                                not('.correct').
                                                length
                                            ) {
                                                alert('Если апелляция полностью удовлетворяется, нужно зачесть все КП');
                                                return false;
                                            }

                                            if (
                                                $(el).
                                                parent().
                                                parent().
                                                find('.status_4').
                                                prop('checked') &&
                                                !$(el).
                                                parent().
                                                parent().
                                                find('.monitor.correct').
                                                length
                                            ) {
                                                var msg =
                                                    'Если апелляция удовлетворяется частично,' +
                                                    'нужно зачесть хотя бы один КП';
                                                alert(msg);
                                                return false;
                                            }
                                        }

                                        function onCancelClick(el) {
                                            $(el).
                                            parent().
                                            parent().
                                            parent().
                                            parent().
                                            parent().
                                            hide().
                                            prev().
                                            toggleClass('row-current');
                                        }
                                        
                                    </script>
                                    <input
                                        type="submit"
                                        style="color: green;"
                                        value="Сохранить"
                                        onclick="return onSaveClick(this)"/>

                                    <button
                                        style="color: red;"
                                        onclick="onCancelClick(this);return false;">
                                        Отмена
                                    </button>
                                </p>
                            </form>
                        </div>
                    </td>
                </tr>
            {/foreach}
        </tbody>
    </table>

    <a href="#" id="action-pending">Проставить</a> выбранным апелляциям статус "на рассмотрении".

    {if $cps_stats}
        <h3>Количество апелляций по КП</h3>
        <table>
            <tr>
                <td>Номер КП</td>
                <td>Количество апелляций</td>
            </tr>
            {foreach from=$cps_stats key=cp_number item=count}
                <tr><td>{$cp_number}</td><td>{$count}</td></tr>
            {/foreach}
        </table>
    {/if}

    <br/>

    <script>
        $(document).ready(function() {
            $.datepicker.setDefaults( $.datepicker.regional[ "ru" ] );
            $( "#appeal_limit" ).datepicker({ dateFormat: "yy-mm-dd" });
        });
    </script>

    <form>
        <table>
            <tr>
                <td>Дата окончания приема апелляций</td>
                <td>
                    <span class="date-wrapper" {if !$competition.appeal_limit}style="display: none;"{/if}>

                        <nobr>
                            <input
                                type="text"
                                name="appeal_limit_dmy"
                                value="{$competition.appeal_limit|date_format:"%Y-%m-%d"}"
                                id="appeal_limit"
                            />
                            <span class="action-datepicker"></span>
                            <select name="appeal_limit_h">
                                {section name=appeal_limit_h_section start=0 loop=24 step=1}
                                    <option
                                        value="{$smarty.section.appeal_limit_h_section.index}"
                                        {if
                                            $competition.appeal_limit|date_format:"%H" eq
                                                $smarty.section.appeal_limit_h_section.index
                                        }
                                            selected="selected"
                                        {/if}
                                    >
                                        {$smarty.section.appeal_limit_h_section.index|string_format:"%02s"}
                                    </option>
                                {/section}
                            </select>
                            <select name="appeal_limit_m">
                                {section name=appeal_limit_m_section start=0 loop=60 step=1}
                                    <option
                                        value="{$smarty.section.appeal_limit_m_section.index}"
                                        {if
                                            $competition.appeal_limit|date_format:"%M" eq
                                                $smarty.section.appeal_limit_m_section.index
                                        }
                                            selected="selected"
                                        {/if}
                                    >
                                        {$smarty.section.appeal_limit_m_section.index|string_format:"%02s"}
                                    </option>
                                {/section}
                            </select>
                        </nobr>
    
                        <br/>
                    </span>

                    NULL
                    <input
                        onclick="$(this).parent().find('.date-wrapper').toggle();"
                        type="checkbox"
                        name="appeal_limit_null"
                        {if !$competition.appeal_limit}checked="checked"{/if}
                    />

                </td>
                <td>
                    Дата и время окончания приема апелляций. Время показывается в UTC.
                </td>
            </tr>

            <tr>
                <td>Лимит времени на подачу апелляций (в часах)</td>
                <td>
                    <input
                        type="text"
                        name="competition_appeal_limit_hours"
                        value="{$competition.appeal_limit_hours}"
                    />
                </td>
                <td>
                    0 - нет ограничения (если не установлена дата окончания приема апелляций выше).
                    Считается от времени публикации результатов.
                </td>
            </tr>

            <tr>
                <td>
                    <input type="hidden" name="action" value="save_comp">
                    <input class="safe-action" type="submit" value="Сохранить"
                </td>
                <td></td>
                <td>
                    <button class="unsafe-action" onclick="window.location.href='?'; return false;">
                        Отмена
                    </button>
                </td>
            </tr>

        </table>
    </form>

</div>

{include file="html_footer.tpl"}

