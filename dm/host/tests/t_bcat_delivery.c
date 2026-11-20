// Exercise the SDK HLE with the real launch-selected snapshot.
#include "../hle_bcat.c"

struct dm_flags g_flag;
uint64_t g_t0_ns;
uint64_t now_ns(void){return 0;}
int dm_guest_as_contains(uintptr_t address){(void)address;return 0;}

#define CHECK(expr) do { if(!(expr)){fprintf(stderr,"BCAT delivery line %d: %s\n",__LINE__,#expr);return 1;} } while(0)
int check_delivery_sdk(const char *name);
int check_delivery_sdk(const char *name){
    uint64_t progress,dir,file,nread;int n;char data[8],names[2][32];BcatEntry entry;
    const unsigned char md5[]={0x7b,0x31,0x47,0xdd,0x46,0x3d,0xe2,0x28,0x89,0x21,0xcc,0x29,0x58,0x12,0xdd,0x94};
    h_bcat_ProgressCtor(&progress);
    if(!name){
        CHECK(h_bcat_Sync(&progress)!=RES_OK);
        CHECK(h_bcat_Enumerate(&n,names,2)!=RES_OK);
        h_bcat_ProgressDtor(&progress);
        return 0;
    }
    CHECK(h_bcat_Sync(&progress)==RES_OK);
    h_bcat_ProgressUpdate(&progress);
    CHECK(h_bcat_ProgressStatus(&progress)==9&&h_bcat_ProgressResult(&progress)==RES_OK);
    CHECK(h_bcat_Enumerate(&n,names,2)==RES_OK&&n==1&&!strcmp(names[0],"normal"));
    h_bcat_DirCtor(&dir);CHECK(h_bcat_DirOpen(&dir,"normal")==RES_OK&&h_bcat_DirCount(&dir)==1);
    CHECK(h_bcat_DirRead(&dir,&n,&entry,1)==RES_OK&&n==1&&!strcmp(entry.name,name)&&entry.size==5&&!memcmp(entry.digest,md5,16));
    h_bcat_FileCtor(&file);CHECK(h_bcat_FileOpen(&file,"normal",name)==RES_OK&&h_bcat_FileSize(&file)==5);
    CHECK(h_bcat_FileRead(&file,&nread,0,data,sizeof data)==RES_OK&&nread==5&&!memcmp(data,"bcat!",5));
    BcatDigest digest=h_bcat_FileDigest(&file);CHECK(!memcmp(&digest,md5,16));
    h_bcat_FileDtor(&file);h_bcat_DirDtor(&dir);h_bcat_ProgressDtor(&progress);
    return 0;
}
