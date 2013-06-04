function updateData(){
    (function(){
        $.ajax({
            url: URL_UPDATE_DATA,
            type: 'GET',
            cache: false,
            timeout: 300000,
            data: {
            },
            success:function(data){
                if(data.status != 'ok'){
                    alert("失敗しました / fail")
                }
                location.href = URL_MYPAGE;
            },
            error:function(jqXHR, textStatus, errorThrown){
                alert('失敗しました / fail');
            },
            beforeSend:function(){ block(); },
            complete:function(){ unblock(); },
            dataType: 'json'
        });
    })();
}

function downloadTlt(book_title, list){
    track_download_tlt_file();
    (function(book_title, list){
        $.ajax({
            url: URL_CREATE_ZIP,
            type: 'POST',
            cache: false,
            timeout: 300000,
            data: {
                book_title: book_title,
                images: list
            },
            success:function(data){
                if(data.status != 'ok'){
                    alert("失敗しました / fail")
                }
                location.href=data.url;
            },
            error:function(jqXHR, textStatus, errorThrown){
                alert('失敗しました / fail');
            },
            beforeSend:function(){ block(); },
            complete:function(){ unblock(); },
            dataType: 'json'
        });
    })(book_title, list);
}

function eraseData(){
    if(confirm('本当に初期化しますか？ / really?')){
        $('#erase_form').submit();
    }
}

function autoSelectFromStart(){
    $(".autoSel").remove();
    console.log('-autoSelectFromStart-');
    var tolot_max_page_num = 62;
    photo_elms = $(".photo:not(.ignore)").get().reverse();

    var i = 1;
    var page = 1;
    var tmp_book_set = [];
    var book_set_list = [];

    $.each(photo_elms, function(){
        //console.log('---');
        //console.log($(this).attr('data-large-image-url'));
        //console.log('page:'+page+'/num'+i);

        $("span", $(this).parent()).text(i).addClass('autoSel');
        tmp_book_set.push($(this).attr('data-large-image-url'));

        i++;
        if(i>tolot_max_page_num){
            var dl_link = $('<a class="btn btn-large btn-success">download #'+page+' tlt set</a>');
            dl_link.attr('data-img-url-list', tmp_book_set.join(','));
            dl_link.click( (function(page){ return function(){
                if(!(book_title = prompt('Please set Photo book Title / タイトルを入力してください', PHOTO_BOOK_TITLE_PREFIX+page))){
                    return false;
                }
                var list = $(this).attr('data-img-url-list').split(',');
                downloadTlt(book_title, list);
                return false;
            }})(page)
            );
            dl_link.attr('href', '#');

            $(this).parent().before($('<div style="text-align:center;padding:10px;margin:10px;"><hr></div>')
                .addClass('autoSel').append(dl_link));

            book_set_list.push(tmp_book_set);
            tmp_book_set = [];

            i=1;
            page++;
        }

    });
    //console.log(book_set_list);
    //console.log(tmp_book_set);
    //console.log('-end-');
}

function setIgnoreImg(elm){
    var img = $(elm);
    if(img.hasClass('ignore')){// ignore済み
        img.removeClass('ignore');
        dataQueue.push({ method:'set_ignore_flag', val:{image:img.attr('data-large-image-url'), flag:0, data_source_table:img.attr("data-source-table") }});
    }else{
        img.addClass('ignore');
        dataQueue.push({ method:'set_ignore_flag', val:{image:img.attr('data-large-image-url'), flag:1, data_source_table:img.attr("data-source-table") }});
    }
    autoSelectFromStart();
};

var dataQueue = [];
var DELAY_DATA_SUBMIT_TIMER = 1000;

function delayDataSubmit(){
    if(dataQueue.length>0){
        indicate_progress();
        var d = dataQueue.pop();
        if(d.method=='set_ignore_flag'){
            console.log(d);
            $.ajax({
                url: URL_SET_IGNORE_FLAG,
                type: 'POST',
                cache: false,
                timeout: 30000,
                data: d.val,
                success:function(data){
                    if(data.status != 'ok'){
                        alert("通信に失敗し、設定できませんでした / operation fail");
                    }else{
                        setTimeout(delayDataSubmit, DELAY_DATA_SUBMIT_TIMER);
                    }
                },
                error:function(jqXHR, textStatus, errorThrown){
                    alert("通信に失敗し、設定できませんでした / operation fail");
                },
                dataType: 'json'
            });
        }
    }else{
        deindicate_progress();
        setTimeout(delayDataSubmit, DELAY_DATA_SUBMIT_TIMER);
    }
}

$(function () {
    autoSelectFromStart();
    $("img.photo").lazyload();
    $("img.photo").click(function(){setIgnoreImg(this);});
    delayDataSubmit();
    if($(".photo").length == 0){//if any photo not found. update once.
        updateData();
    }
});
